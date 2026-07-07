using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;

namespace MegaBackupWsl.FastWpf
{
    internal sealed class PowerShellBackupRunner
    {
        private readonly object _syncRoot = new object();
        private Process _currentProcess;

        public int Run(
            string repoRoot,
            string scriptPath,
            List<string> args,
            Action<string> appendLog)
        {
            appendLog("Comando: " + BackupScriptCommand.ToLogText(scriptPath, args));

            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = repoRoot,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
                Arguments = BackupScriptCommand.ToPowerShellArguments(scriptPath, args)
            };

            using (var process = new Process())
            {
                process.StartInfo = startInfo;
                process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
                {
                    if (e.Data != null)
                    {
                        appendLog(e.Data);
                    }
                };
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
                {
                    if (e.Data != null)
                    {
                        appendLog(e.Data);
                    }
                };

                try
                {
                    process.Start();
                    SetCurrentProcess(process);
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();
                    process.WaitForExit();
                    appendLog("Codigo de saida: " + process.ExitCode);
                    return process.ExitCode;
                }
                finally
                {
                    ClearCurrentProcess(process);
                }
            }
        }

        public void Stop(Action<string> appendLog)
        {
            var process = GetCurrentProcess();

            if (process == null || process.HasExited)
            {
                return;
            }

            process.Kill();
            appendLog("Processo interrompido pelo usuario.");
        }

        private void SetCurrentProcess(Process process)
        {
            lock (_syncRoot)
            {
                _currentProcess = process;
            }
        }

        private void ClearCurrentProcess(Process process)
        {
            lock (_syncRoot)
            {
                if (ReferenceEquals(_currentProcess, process))
                {
                    _currentProcess = null;
                }
            }
        }

        private Process GetCurrentProcess()
        {
            lock (_syncRoot)
            {
                return _currentProcess;
            }
        }
    }
}
