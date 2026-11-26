"""Provision a dedicated Xray instance on an authorized Debian systemd host."""
import argparse
import ipaddress
import json
import os
import pwd
import secrets
import shutil
import socket
import subprocess
import tempfile
import uuid
from pathlib import Path


NAME = 'net-claude-chain'
GUARD = NAME + '-guard'
DEST = Path('/etc/net-claude-chain')
TABLE = 'net_claude_chain'
XRAY = Path('/usr/local/lib/net-claude-chain/xray')
NFT = Path('/usr/sbin/nft')


def run(*args, capture=False):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE if capture else None).stdout


def write(path, data, mode, gid=0):
    fd, temp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(data.encode() if isinstance(data, str) else data)
        os.chown(temp, 0, gid)
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def new_xray():
    import hashlib
    import urllib.request
    import zipfile

    if XRAY.is_file():
        return
    arch = run('dpkg', '--print-architecture', capture=True).strip()
    asset_name = {
        'amd64': 'Xray-linux-64.zip',
        'arm64': 'Xray-linux-arm64-v8a.zip',
    }.get(arch)
    if not asset_name:
        raise SystemExit(f'Unsupported Debian architecture: {arch}')
    request = urllib.request.Request(
        'https://api.github.com/repos/XTLS/Xray-core/releases/latest',
        headers={'User-Agent': NAME, 'Accept': 'application/vnd.github+json'},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        release = json.load(response)
    asset = next((item for item in release['assets'] if item['name'] == asset_name), None)
    prefix = 'https://github.com/XTLS/Xray-core/releases/download/'
    if not asset or not asset.get('digest', '').startswith('sha256:') or not asset['browser_download_url'].startswith(prefix):
        raise SystemExit('The official Xray archive or its SHA-256 digest is unavailable.')
    with tempfile.TemporaryDirectory(prefix=NAME + '-') as stage:
        archive = Path(stage) / asset_name
        digest = hashlib.sha256()
        with urllib.request.urlopen(asset['browser_download_url'], timeout=60) as source, archive.open('wb') as output:
            for block in iter(lambda: source.read(1024 * 1024), b''):
                digest.update(block)
                output.write(block)
        if digest.hexdigest() != asset['digest'].removeprefix('sha256:'):
            raise SystemExit('The official Xray archive did not match its SHA-256 digest.')
        XRAY.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as bundle:
            for name, mode in [('geoip.dat', 0o644), ('geosite.dat', 0o644), ('xray', 0o755)]:
                with bundle.open(name) as item:
                    write(XRAY.parent / name, item.read(), mode)


def prepare_host():
    if os.geteuid() != 0:
        raise SystemExit('Root or sudo is required.')
    if 'ID=debian' not in Path('/etc/os-release').read_text(encoding='utf-8').splitlines():
        raise SystemExit('This installer targets Debian.')
    if not NFT.is_file():
        run('apt-get', 'update')
        run('apt-get', 'install', '-y', '--no-install-recommends', 'nftables', 'ca-certificates')
    new_xray()


def deploy(args):
    prepare_host()
    if args.credentials.stat().st_mode & 0o077:
        raise SystemExit('Protect the input with mode 0600 before running.')
    if DEST.exists():
        raise SystemExit('Dedicated config already exists. Inspect and verify it before changing it.')
    with args.credentials.open(encoding='utf-8') as handle:
        auth = json.load(handle)
    upstream = str(ipaddress.IPv4Address(auth['proxy_ip']))
    port = int(auth['proxy_port'])
    if not 1 <= port <= 65535 or not auth['username'] or not auth['password']:
        raise SystemExit('Invalid proxy port or authentication fields.')
    vps = str(ipaddress.IPv4Address(args.vps_ip))
    target = socket.getaddrinfo(args.sni, 443, socket.AF_INET, socket.SOCK_STREAM)[0][4][0]
    # Bind-test before writing configuration or starting services.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(('0.0.0.0', args.listen))
    keys = dict(line.split(':', 1) for line in run(str(XRAY), 'x25519', capture=True).splitlines() if ':' in line)
    private = (keys.get('PrivateKey') or keys.get('Private key') or '').strip()
    public = (keys.get('Password (PublicKey)') or keys.get('PublicKey') or keys.get('Public key') or '').strip()
    if len(private) != 43 or len(public) != 43:
        raise SystemExit('Xray key format was not recognized.')
    try:
        user = pwd.getpwnam(NAME)
    except KeyError:
        run('useradd', '--system', '--no-create-home', '--shell', '/usr/sbin/nologin', NAME)
        user = pwd.getpwnam(NAME)
    sid, client_id = secrets.token_hex(8), str(uuid.uuid4())
    client_identity = {'id': client_id, 'flow': 'xtls-rprx-vision'}
    server = {
        'log': {'loglevel': 'warning'},
        'inbounds': [{'listen': '0.0.0.0', 'port': args.listen, 'protocol': 'vless',
                      'settings': {'clients': [client_identity], 'decryption': 'none'},
                      'streamSettings': {'network': 'tcp', 'security': 'reality',
                                         'realitySettings': {'target': f'{target}:443', 'serverNames': [args.sni],
                                                             'privateKey': private, 'shortIds': [sid]}}}],
        'outbounds': [
            {'tag': 'resi', 'protocol': 'socks', 'settings': {'servers': [
                {'address': upstream, 'port': port, 'users': [{'user': auth['username'], 'pass': auth['password']}]}]}},
            {'tag': 'block', 'protocol': 'blackhole'}],
        'routing': {'domainStrategy': 'AsIs', 'rules': [
            {'type': 'field', 'network': 'udp', 'outboundTag': 'block'},
            {'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'block'}]},
    }
    client = {
        'log': {'loglevel': 'warning'},
        'inbounds': [{'port': args.local_port, 'listen': '127.0.0.1', 'protocol': 'http', 'settings': {}}],
        'outbounds': [{'protocol': 'vless', 'settings': {'vnext': [{'address': vps, 'port': args.listen,
                       'users': [{**client_identity, 'encryption': 'none'}]}]},
                       'streamSettings': {'network': 'tcp', 'security': 'reality',
                                          'realitySettings': {'serverName': args.sni, 'publicKey': public,
                                                              'shortId': sid, 'fingerprint': 'chrome'}}}],
    }
    guard = f"""table inet {TABLE} {{
 chain output {{
  type filter hook output priority -10; policy accept;
  meta skuid {user.pw_uid} oif lo accept
  meta skuid {user.pw_uid} ct state established,related accept
  meta skuid {user.pw_uid} ip daddr {upstream} tcp dport {port} accept
  meta skuid {user.pw_uid} ip daddr {target} tcp dport 443 accept
  meta skuid {user.pw_uid} counter drop
 }}
}}
"""
    guard_unit = f"""[Unit]
After=nftables.service
Before={NAME}.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart={NFT} -f {DEST}/guard.nft
ExecStop={NFT} delete table inet {TABLE}
[Install]
WantedBy=multi-user.target
"""
    service = f"""[Unit]
After=network-online.target {GUARD}.service
Wants=network-online.target
BindsTo={GUARD}.service
[Service]
User={NAME}
Group={NAME}
ExecStart={XRAY} run -c {DEST}/server.json
Restart=on-failure
RestartSec=5
Environment=XRAY_LOCATION_ASSET=/usr/local/lib/net-claude-chain
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
[Install]
WantedBy=multi-user.target
"""
    units = Path('/etc/systemd/system')
    unit_paths = [units / (GUARD + '.service'), units / (NAME + '.service')]
    if any(path.exists() for path in unit_paths):
        raise SystemExit('Existing dedicated unit files require review.')
    DEST.mkdir(mode=0o750)
    try:
        os.chown(DEST, 0, user.pw_gid)
        write(DEST / 'server.json', json.dumps(server), 0o640, user.pw_gid)
        write(DEST / 'client.json', json.dumps(client), 0o600)
        write(DEST / 'guard.nft', guard, 0o600)
        run('env', 'XRAY_LOCATION_ASSET=' + str(XRAY.parent), str(XRAY), 'run', '-test', '-c', str(DEST / 'server.json'))
        run(str(NFT), '-c', '-f', str(DEST / 'guard.nft'))
        write(unit_paths[0], guard_unit, 0o644)
        write(unit_paths[1], service, 0o644)
        run('systemctl', 'daemon-reload')
        run('systemd-run', '--unit=' + NAME + '-safety', '--on-active=180',
            '/usr/bin/systemctl', 'stop', NAME + '.service', GUARD + '.service')
        run('systemctl', 'start', NAME + '.service')
        run('systemctl', 'is-active', NAME + '.service')
    except Exception:
        subprocess.run(['systemctl', 'stop', NAME + '.service', GUARD + '.service', NAME + '-safety.timer'], check=False)
        for path in unit_paths:
            path.unlink(missing_ok=True)
        shutil.rmtree(DEST)
        subprocess.run(['systemctl', 'daemon-reload'], check=False)
        raise
    print(f'Client config saved to {DEST}/client.json. Verify end to end before cancelling the safety timer and enabling services.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--vps-ip', required=True)
    parser.add_argument('--credentials', required=True, type=Path)
    parser.add_argument('--sni', default='www.microsoft.com')
    parser.add_argument('--listen', type=int, default=443, choices=range(1, 65536), metavar='PORT')
    parser.add_argument('--local-port', type=int, default=10810, choices=range(1, 65536), metavar='PORT')
    deploy(parser.parse_args())
