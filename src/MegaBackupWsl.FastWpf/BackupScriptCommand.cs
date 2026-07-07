using System.Collections.Generic;
using System.Linq;

namespace MegaBackupWsl.FastWpf
{
    internal static class BackupScriptCommand
    {
        public static List<string> WithCommonOptions(
            string backupRoot,
            string sourceVhdx,
            params string[] args)
        {
            var result = new List<string>(args ?? new string[0]);

            result.Add("-BackupRoot");
            result.Add((backupRoot ?? string.Empty).Trim());

            var vhdx = (sourceVhdx ?? string.Empty).Trim();
            if (!string.IsNullOrWhiteSpace(vhdx))
            {
                result.Add("-SourceVhdx");
                result.Add(vhdx);
            }

            return result;
        }

        public static string ToLogText(string scriptPath, IEnumerable<string> args)
        {
            return "powershell.exe -File " + Quote(scriptPath) + " " + FormatArgs(args);
        }

        public static string ToPowerShellArguments(string scriptPath, IEnumerable<string> args)
        {
            return "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File " +
                Quote(scriptPath) + " " +
                FormatArgs(args);
        }

        private static string FormatArgs(IEnumerable<string> args)
        {
            return string.Join(" ", (args ?? Enumerable.Empty<string>()).Select(Quote).ToArray());
        }

        private static string Quote(string arg)
        {
            if (arg == null)
            {
                return "\"\"";
            }

            return arg.IndexOfAny(new[] { ' ', '\t', '"' }) >= 0
                ? "\"" + arg.Replace("\"", "\\\"") + "\""
                : arg;
        }
    }
}
