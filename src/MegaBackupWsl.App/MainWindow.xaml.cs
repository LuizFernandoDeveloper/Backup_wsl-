using Microsoft.Win32;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using Forms = System.Windows.Forms;

namespace MegaBackupWsl.App;

public partial class MainWindow : Window
{
    private readonly string? _repoRoot;
    private readonly string? _scriptPath;
    private Process? _runningProcess;
    private bool _isBusy;

    public MainWindow()
    {
        InitializeComponent();

        _repoRoot = LocateRepositoryRoot();
        _scriptPath = _repoRoot is null
            ? null
            : Path.Combine(_repoRoot, "scripts", "Mega_Backup_WSL.ps1");

        ScriptPathText.Text = _scriptPath is null
            ? "Script nao encontrado. Mantenha o executavel dentro do repositorio ou ao lado das pastas scripts e launchers."
            : $"Script: {_scriptPath}";

        if (_scriptPath is null || !File.Exists(_scriptPath))
        {
            AppendLog("ERRO: scripts\\Mega_Backup_WSL.ps1 nao encontrado.");
            SetBusyState(false, "Script ausente");
        }
    }

    private static string? LocateRepositoryRoot()
    {
        var candidates = new[]
        {
            AppContext.BaseDirectory,
            Environment.CurrentDirectory
        };

        foreach (var candidate in candidates)
        {
            var directory = new DirectoryInfo(candidate);

            while (directory is not null)
            {
                var scriptPath = Path.Combine(directory.FullName, "scripts", "Mega_Backup_WSL.ps1");

                if (File.Exists(scriptPath))
                {
                    return directory.FullName;
                }

                directory = directory.Parent;
            }
        }

        return null;
    }

    private void BrowseBackupRoot_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new Forms.FolderBrowserDialog
        {
            Description = "Selecione a pasta raiz do backup WSL",
            SelectedPath = BackupRootTextBox.Text
        };

        if (dialog.ShowDialog() == Forms.DialogResult.OK)
        {
            BackupRootTextBox.Text = dialog.SelectedPath;
        }
    }

    private void BrowseSourceVhdx_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "Selecione o WSL_Drives.vhdx",
            Filter = "VHDX (*.vhdx)|*.vhdx|Todos os arquivos (*.*)|*.*",
            FileName = SourceVhdxTextBox.Text
        };

        if (dialog.ShowDialog(this) == true)
        {
            SourceVhdxTextBox.Text = dialog.FileName;
        }
    }

    private async void DryRunOrganize_Click(object sender, RoutedEventArgs e)
    {
        await RunSingleCommandAsync("Simular organizacao", BuildCommonArgs("-OrganizeRuns", "-DryRun"));
    }

    private async void OrganizeRuns_Click(object sender, RoutedEventArgs e)
    {
        await RunSingleCommandAsync("Organizar diretorios", BuildCommonArgs("-OrganizeRuns"));
    }

    private async void DryRunBackup_Click(object sender, RoutedEventArgs e)
    {
        await RunSingleCommandAsync(
            "DryRun completo",
            BuildCommonArgs("-BackupMode", SelectedText(BackupModeComboBox), "-QualityGate", SelectedText(QualityGateComboBox), "-DryRun"));
    }

    private async void HealthOnly_Click(object sender, RoutedEventArgs e)
    {
        await RunSingleCommandAsync(
            "Saude das distros",
            BuildCommonArgs("-BackupMode", "Distros", "-QualityGate", SelectedText(QualityGateComboBox), "-HealthOnly"));
    }

    private async void FullTemplate_Click(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            this,
            "O Full Template pode desligar o WSL durante a etapa de backup real. Feche terminais e servicos dentro das distros antes de continuar.",
            "Confirmar Full Template",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);

        if (result != MessageBoxResult.OK)
        {
            return;
        }

        if (!BeginRun("Full Template"))
        {
            return;
        }

        try
        {
            var purifyExit = await RunPowerShellAsync(BuildCommonArgs("-BackupMode", "Distros", "-PurifyOnly", "-QualityGate", "Template"));

            if (purifyExit != 0)
            {
                AppendLog($"Full Template interrompido: purificacao retornou codigo {purifyExit}.");
                SetBusyState(false, "Falhou");
                return;
            }

            AppendLog("");
            AppendLog("Purificacao aprovada. Iniciando backup completo Template...");
            var backupExit = await RunPowerShellAsync(BuildCommonArgs("-BackupMode", "All", "-QualityGate", "Template"));

            SetBusyState(false, backupExit == 0 ? "Concluido" : $"Falhou: {backupExit}");
        }
        catch (Exception ex)
        {
            AppendLog($"ERRO: {ex.Message}");
            SetBusyState(false, "Erro");
        }
    }

    private void StopProcess_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (_runningProcess is not null && !_runningProcess.HasExited)
            {
                _runningProcess.Kill(entireProcessTree: true);
                AppendLog("Processo interrompido pelo usuario.");
            }
        }
        catch (Exception ex)
        {
            AppendLog($"ERRO ao interromper: {ex.Message}");
        }
    }

    private void ClearLog_Click(object sender, RoutedEventArgs e)
    {
        LogTextBox.Clear();
    }

    private async Task RunSingleCommandAsync(string title, IReadOnlyList<string> args)
    {
        if (!BeginRun(title))
        {
            return;
        }

        try
        {
            var exitCode = await RunPowerShellAsync(args);
            SetBusyState(false, exitCode == 0 ? "Concluido" : $"Falhou: {exitCode}");
        }
        catch (Exception ex)
        {
            AppendLog($"ERRO: {ex.Message}");
            SetBusyState(false, "Erro");
        }
    }

    private bool BeginRun(string title)
    {
        if (_isBusy)
        {
            return false;
        }

        if (_scriptPath is null || !File.Exists(_scriptPath))
        {
            MessageBox.Show(this, "Script PowerShell nao encontrado.", "Mega Backup WSL", MessageBoxButton.OK, MessageBoxImage.Error);
            return false;
        }

        AppendLog("");
        AppendLog($"=== {title} ===");
        SetBusyState(true, "Executando");
        return true;
    }

    private IReadOnlyList<string> BuildCommonArgs(params string[] args)
    {
        var result = new List<string>(args)
        {
            "-BackupRoot",
            BackupRootTextBox.Text.Trim()
        };

        var sourceVhdx = SourceVhdxTextBox.Text.Trim();

        if (!string.IsNullOrWhiteSpace(sourceVhdx))
        {
            result.Add("-SourceVhdx");
            result.Add(sourceVhdx);
        }

        return result;
    }

    private async Task<int> RunPowerShellAsync(IReadOnlyList<string> scriptArgs)
    {
        if (_scriptPath is null)
        {
            throw new InvalidOperationException("Script PowerShell nao localizado.");
        }

        AppendLog($"Comando: powershell.exe -File \"{_scriptPath}\" {FormatArgs(scriptArgs)}");

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = _repoRoot ?? Environment.CurrentDirectory,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        startInfo.ArgumentList.Add("-NoLogo");
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("RemoteSigned");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(_scriptPath);

        foreach (var arg in scriptArgs)
        {
            startInfo.ArgumentList.Add(arg);
        }

        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        _runningProcess = process;

        process.OutputDataReceived += (_, eventArgs) =>
        {
            if (eventArgs.Data is not null)
            {
                AppendLog(eventArgs.Data);
            }
        };

        process.ErrorDataReceived += (_, eventArgs) =>
        {
            if (eventArgs.Data is not null)
            {
                AppendLog(eventArgs.Data);
            }
        };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        await process.WaitForExitAsync();
        _runningProcess = null;

        AppendLog($"Codigo de saida: {process.ExitCode}");
        return process.ExitCode;
    }

    private static string SelectedText(ComboBox comboBox)
    {
        return ((ComboBoxItem)comboBox.SelectedItem).Content?.ToString() ?? "";
    }

    private static string FormatArgs(IEnumerable<string> args)
    {
        return string.Join(" ", args.Select(QuoteArg));
    }

    private static string QuoteArg(string arg)
    {
        return arg.Any(char.IsWhiteSpace) ? $"\"{arg.Replace("\"", "\\\"")}\"" : arg;
    }

    private void SetBusyState(bool isBusy, string status)
    {
        _isBusy = isBusy;
        StatusText.Text = status;
        StopButton.IsEnabled = isBusy;
    }

    private void AppendLog(string text)
    {
        Dispatcher.BeginInvoke(new Action(() =>
        {
            LogTextBox.AppendText(text + Environment.NewLine);
            LogTextBox.ScrollToEnd();
        }));
    }
}
