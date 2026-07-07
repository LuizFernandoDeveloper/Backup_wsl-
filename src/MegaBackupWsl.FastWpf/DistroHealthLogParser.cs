using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace MegaBackupWsl.FastWpf
{
    internal static class DistroHealthLogParser
    {
        private static readonly Regex HealthLineRegex = new Regex(
            @"Saude (?<name>.+?): (?<status>OK|WARN|ERROR) \| / usado: (?<root>\d+)% \| / livre: (?<free>.*?) \| inodes: (?<inode>\d+)% \| sockets temporarios: (?<sockets>\d+) \| VHDX: (?<vhdx>.*)$",
            RegexOptions.Compiled);

        private static readonly Regex WarningLineRegex = new Regex(
            @"Alertas (?<name>.+?): (?<warnings>.*)$",
            RegexOptions.Compiled);

        private static readonly Regex DeepHealthLineRegex = new Regex(
            @"Diagnostico pesado (?<name>.+?): sockets totais: (?<sockets>\d+) \| links quebrados: (?<links>\d+) \| root read-only: (?<readonly>True|False) \| /tmp escrita: (?<tmp>True|False) \| \$HOME escrita: (?<home>True|False) \| erros find: (?<find>\d+)",
            RegexOptions.Compiled);

        private static readonly Regex DirectoryIssueLineRegex = new Regex(
            @"Erros de diretorio (?<name>.+?): (?<issue>.*)$",
            RegexOptions.Compiled);

        private static readonly Regex DmesgIssueLineRegex = new Regex(
            @"Sinais no dmesg (?<name>.+?): (?<issue>.*)$",
            RegexOptions.Compiled);

        public static bool Parse(
            string text,
            Func<string, DistroHealthViewModel> getHealthRow,
            Action refreshDashboard)
        {
            if (string.IsNullOrWhiteSpace(text))
            {
                return false;
            }

            if (ParseUiEventLine(text, getHealthRow, refreshDashboard))
            {
                return true;
            }

            var healthMatch = HealthLineRegex.Match(text);
            if (healthMatch.Success)
            {
                var health = getHealthRow(healthMatch.Groups["name"].Value);
                health.Status = healthMatch.Groups["status"].Value.Trim();
                health.RootUsedPercent = ReadInt(healthMatch.Groups["root"].Value);
                health.RootFree = healthMatch.Groups["free"].Value.Trim();
                health.InodeUsedPercent = ReadInt(healthMatch.Groups["inode"].Value);
                health.TemporarySockets = ReadLong(healthMatch.Groups["sockets"].Value);
                health.Vhdx = healthMatch.Groups["vhdx"].Value.Trim();
                refreshDashboard();
                return false;
            }

            var warningMatch = WarningLineRegex.Match(text);
            if (warningMatch.Success)
            {
                var health = getHealthRow(warningMatch.Groups["name"].Value);
                var warnings = warningMatch.Groups["warnings"].Value.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries);

                foreach (var warning in warnings)
                {
                    health.AddWarning(warning.Trim());
                }

                refreshDashboard();
                return false;
            }

            var deepMatch = DeepHealthLineRegex.Match(text);
            if (deepMatch.Success)
            {
                var health = getHealthRow(deepMatch.Groups["name"].Value);
                health.AllSockets = ReadLong(deepMatch.Groups["sockets"].Value);
                health.BrokenLinks = ReadLong(deepMatch.Groups["links"].Value);
                health.RootReadOnly = ReadBool(deepMatch.Groups["readonly"].Value);
                health.TmpWritable = ReadBool(deepMatch.Groups["tmp"].Value);
                health.HomeWritable = ReadBool(deepMatch.Groups["home"].Value);
                health.FindErrorCount = ReadLong(deepMatch.Groups["find"].Value);
                AddDerivedWarnings(health);
                refreshDashboard();
                return false;
            }

            var directoryMatch = DirectoryIssueLineRegex.Match(text);
            if (directoryMatch.Success)
            {
                getHealthRow(directoryMatch.Groups["name"].Value).AddWarning("erros de diretorio");
                refreshDashboard();
                return false;
            }

            var dmesgMatch = DmesgIssueLineRegex.Match(text);
            if (dmesgMatch.Success)
            {
                getHealthRow(dmesgMatch.Groups["name"].Value).AddWarning("dmesg com sinal grave");
                refreshDashboard();
            }

            return false;
        }

        private static bool ParseUiEventLine(
            string text,
            Func<string, DistroHealthViewModel> getHealthRow,
            Action refreshDashboard)
        {
            const string prefix = "MBWSL_UI_EVENT ";

            if (!text.StartsWith(prefix, StringComparison.Ordinal))
            {
                return false;
            }

            var fields = ParseUiEventFields(text.Substring(prefix.Length));
            string eventName;

            if (!fields.TryGetValue("Event", out eventName) ||
                !string.Equals(eventName, "DistroHealth", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            ApplyDistroHealthEvent(fields, getHealthRow);
            refreshDashboard();
            return true;
        }

        private static void ApplyDistroHealthEvent(
            Dictionary<string, string> fields,
            Func<string, DistroHealthViewModel> getHealthRow)
        {
            string name;
            if (!fields.TryGetValue("Name", out name))
            {
                name = "Desconhecida";
            }

            var health = getHealthRow(name);
            string value;

            if (fields.TryGetValue("Status", out value))
            {
                health.Status = value;
            }

            if (fields.TryGetValue("RootUsedPercent", out value))
            {
                health.RootUsedPercent = ReadInt(value);
            }

            if (fields.TryGetValue("RootFree", out value))
            {
                health.RootFree = value;
            }

            if (fields.TryGetValue("InodeUsedPercent", out value))
            {
                health.InodeUsedPercent = ReadInt(value);
            }

            if (fields.TryGetValue("TemporarySockets", out value))
            {
                health.TemporarySockets = ReadLong(value);
            }

            if (fields.TryGetValue("AllSockets", out value))
            {
                health.AllSockets = ReadLong(value);
            }

            if (fields.TryGetValue("BrokenLinks", out value))
            {
                health.BrokenLinks = ReadLong(value);
            }

            if (fields.TryGetValue("FindErrorCount", out value))
            {
                health.FindErrorCount = ReadLong(value);
            }

            if (fields.TryGetValue("RootReadOnly", out value))
            {
                health.RootReadOnly = ReadBool(value);
            }

            if (fields.TryGetValue("TmpWritable", out value))
            {
                health.TmpWritable = ReadBool(value);
            }

            if (fields.TryGetValue("HomeWritable", out value))
            {
                health.HomeWritable = ReadBool(value);
            }

            if (fields.TryGetValue("Vhdx", out value))
            {
                health.Vhdx = value;
            }

            if (fields.TryGetValue("Warnings", out value) && !string.IsNullOrWhiteSpace(value))
            {
                var warnings = value.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries);

                foreach (var warning in warnings)
                {
                    health.AddWarning(warning.Trim());
                }
            }

            AddDerivedWarnings(health);
        }

        private static void AddDerivedWarnings(DistroHealthViewModel health)
        {
            if (health.RootReadOnly)
            {
                health.AddWarning("root read-only");
            }

            if (!health.TmpWritable)
            {
                health.AddWarning("/tmp sem escrita");
            }

            if (!health.HomeWritable)
            {
                health.AddWarning("$HOME sem escrita");
            }

            if (health.FindErrorCount > 0)
            {
                health.AddWarning(health.FindErrorCount + " erro(s) de diretorio");
            }

            if (health.BrokenLinks > 0)
            {
                health.AddWarning(health.BrokenLinks + " link(s) quebrado(s)");
            }
        }

        private static Dictionary<string, string> ParseUiEventFields(string payload)
        {
            var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var parts = payload.Split(new[] { '|' }, StringSplitOptions.RemoveEmptyEntries);

            foreach (var part in parts)
            {
                var separator = part.IndexOf('=');

                if (separator <= 0)
                {
                    continue;
                }

                var key = part.Substring(0, separator);
                var value = part.Substring(separator + 1);
                result[key] = Uri.UnescapeDataString(value);
            }

            return result;
        }

        private static int ReadInt(string value)
        {
            int result;
            return int.TryParse((value ?? string.Empty).Trim(), out result) ? result : 0;
        }

        private static long ReadLong(string value)
        {
            long result;
            return long.TryParse((value ?? string.Empty).Trim(), out result) ? result : 0;
        }

        private static bool ReadBool(string value)
        {
            return string.Equals((value ?? string.Empty).Trim(), "True", StringComparison.OrdinalIgnoreCase);
        }
    }
}
