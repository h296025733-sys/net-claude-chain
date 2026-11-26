if (WScript.Arguments.length !== 1) {
    WScript.Quit(2);
}

var mode = WScript.Arguments.Item(0);
if (mode !== "Web" && mode !== "Desktop" && mode !== "Check") {
    WScript.Quit(2);
}

var shell = new ActiveXObject("WScript.Shell");
var files = new ActiveXObject("Scripting.FileSystemObject");
var root = files.GetParentFolderName(WScript.ScriptFullName);
var powershell = shell.ExpandEnvironmentStrings("%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe");
var launcher = files.BuildPath(root, "claude-client.ps1");
var command = '"' + powershell + '" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden' +
    ' -ExecutionPolicy Bypass -File "' + launcher + '" -Mode ' + mode;
shell.Run(command, 0, false);
