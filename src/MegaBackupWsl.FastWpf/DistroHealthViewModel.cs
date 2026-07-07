using System;
using System.Collections.Generic;
using System.Linq;

namespace MegaBackupWsl.FastWpf
{
    internal sealed class DistroHealthViewModel
    {
        public readonly List<string> Warnings;

        public DistroHealthViewModel(string name)
        {
            Name = name;
            Status = "OK";
            RootFree = "-";
            Vhdx = "-";
            TmpWritable = true;
            HomeWritable = true;
            Warnings = new List<string>();
        }

        public string Name { get; private set; }
        public string Status { get; set; }
        public int RootUsedPercent { get; set; }
        public int InodeUsedPercent { get; set; }
        public long TemporarySockets { get; set; }
        public long AllSockets { get; set; }
        public long BrokenLinks { get; set; }
        public long FindErrorCount { get; set; }
        public bool RootReadOnly { get; set; }
        public bool TmpWritable { get; set; }
        public bool HomeWritable { get; set; }
        public string RootFree { get; set; }
        public string Vhdx { get; set; }

        public int RiskScore
        {
            get
            {
                var score = Warnings.Count;

                if (TemporarySockets > 0)
                {
                    score += (int)Math.Min(10, TemporarySockets);
                }

                if (BrokenLinks > 0)
                {
                    score += (int)Math.Min(6, BrokenLinks);
                }

                if (FindErrorCount > 0)
                {
                    score += (int)Math.Min(8, FindErrorCount);
                }

                if (RootReadOnly)
                {
                    score += 10;
                }

                if (!TmpWritable)
                {
                    score += 6;
                }

                if (!HomeWritable)
                {
                    score += 6;
                }

                return score;
            }
        }

        public string WarningSummary
        {
            get
            {
                if (Warnings.Count == 0)
                {
                    return "Sem alertas";
                }

                return string.Join("; ", Warnings.Take(4).ToArray());
            }
        }

        public void AddWarning(string warning)
        {
            if (string.IsNullOrWhiteSpace(warning))
            {
                return;
            }

            if (!Warnings.Any(item => string.Equals(item, warning, StringComparison.OrdinalIgnoreCase)))
            {
                Warnings.Add(warning);
            }
        }
    }
}
