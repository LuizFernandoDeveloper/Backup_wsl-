using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace MegaBackupWsl.FastWpf
{
    public sealed class Program : Application
    {
        private string _repoRoot;
        private string _scriptPath;
        private Process _runningProcess;
        private TextBox _backupRootTextBox;
        private TextBox _sourceVhdxTextBox;
        private ComboBox _backupModeComboBox;
        private ComboBox _qualityGateComboBox;
        private TextBox _logTextBox;
        private TextBlock _statusText;
        private Button _stopButton;
        private bool _busy;

        [STAThread]
        public static void Main()
        {
            var app = new Program();
            app.Run(app.CreateMainWindow());
        }

        private Window CreateMainWindow()
        {
            _repoRoot = LocateRepositoryRoot();
            _scriptPath = Path.Combine(_repoRoot ?? string.Empty, "scripts", "Mega_Backup_WSL.ps1");

            var window = new Window
            {
                Title = "Mega Backup WSL",
                Width = 1120,
                Height = 760,
                MinWidth = 960,
                MinHeight = 640,
                WindowStartupLocation = WindowStartupLocation.CenterScreen,
                Background = Brush("#F8FAFC"),
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 13
            };

            var root = new Grid { Margin = new Thickness(18) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            window.Content = root;

            AddHeader(root);
            AddSettings(root);
            AddBody(root);
            AddFooter(root);

            if (string.IsNullOrWhiteSpace(_repoRoot) || !File.Exists(_scriptPath))
            {
                AppendLog("ERRO: scripts\\Mega_Backup_WSL.ps1 nao encontrado.");
                SetBusy(false, "Script ausente");
            }

            return window;
        }

        private void AddHeader(Grid root)
        {
            var border = PanelBorder();
            border.Padding = new Thickness(18);
            Grid.SetRow(border, 0);
            root.Children.Add(border);

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            border.Child = grid;

            var titleStack = new StackPanel();
            titleStack.Children.Add(new TextBlock
            {
                Text = "Mega Backup WSL",
                FontSize = 24,
                FontWeight = FontWeights.SemiBold
            });
            titleStack.Children.Add(new TextBlock
            {
                Text = "Interface .exe para organizar backups, validar templates e executar rotinas seguras.",
                Margin = new Thickness(0, 5, 0, 0),
                Foreground = Brush("#64748B")
            });
            grid.Children.Add(titleStack);

            var statusBorder = new Border
            {
                Background = Brush("#ECFDF5"),
                BorderBrush = Brush("#99F6E4"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(16),
                Padding = new Thickness(14, 7, 14, 7),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(statusBorder, 1);
            _statusText = new TextBlock
            {
                Text = "Pronto",
                Foreground = Brush("#134E4A"),
                FontWeight = FontWeights.SemiBold
            };
            statusBorder.Child = _statusText;
            grid.Children.Add(statusBorder);
        }

        private void AddSettings(Grid root)
        {
            var border = PanelBorder();
            border.Margin = new Thickness(0, 14, 0, 14);
            border.Padding = new Thickness(18);
            Grid.SetRow(border, 1);
            root.Children.Add(border);

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            border.Child = grid;

            AddLabel(grid, "BackupRoot", 0);
            AddLabel(grid, "SourceVhdx", 1);
            AddLabel(grid, "BackupMode", 2);
            AddLabel(grid, "QualityGate", 3);

            _backupRootTextBox = Input("F:\\Backup\\WSl_backup");
            AddBrowseInput(grid, _backupRootTextBox, 0, BrowseBackupRoot);

            _sourceVhdxTextBox = Input("D:\\disk-removivel-wsl2\\WSL_Drives.vhdx");
            AddBrowseInput(grid, _sourceVhdxTextBox, 1, BrowseSourceVhdx);

            _backupModeComboBox = Combo("All", "Distros", "Vhdx");
            Grid.SetRow(_backupModeComboBox, 1);
            Grid.SetColumn(_backupModeComboBox, 2);
            _backupModeComboBox.Margin = new Thickness(0, 6, 14, 0);
            grid.Children.Add(_backupModeComboBox);

            _qualityGateComboBox = Combo("Basic", "Standard", "Template");
            _qualityGateComboBox.SelectedIndex = 1;
            Grid.SetRow(_qualityGateComboBox, 1);
            Grid.SetColumn(_qualityGateComboBox, 3);
            _qualityGateComboBox.Margin = new Thickness(0, 6, 0, 0);
            grid.Children.Add(_qualityGateComboBox);
        }

        private void AddBody(Grid root)
        {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(300) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetRow(grid, 2);
            root.Children.Add(grid);

            var actions = PanelBorder();
            actions.Padding = new Thickness(16);
            actions.Margin = new Thickness(0, 0, 14, 0);
            Grid.SetColumn(actions, 0);
            grid.Children.Add(actions);

            var stack = new StackPanel();
            actions.Child = stack;
            stack.Children.Add(new TextBlock
            {
                Text = "Acoes Rapidas",
                FontSize = 17,
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 0, 0, 12)
            });

            AddActionButton(stack, "Simular Organizacao", false, delegate { RunSingle("Simular organizacao", Args("-OrganizeRuns", "-DryRun")); });
            AddActionButton(stack, "Organizar Diretorios", true, delegate { RunSingle("Organizar diretorios", Args("-OrganizeRuns")); });
            stack.Children.Add(new Separator { Margin = new Thickness(0, 6, 0, 14) });
            AddActionButton(stack, "DryRun Completo", false, delegate { RunSingle("DryRun completo", Args("-BackupMode", Selected(_backupModeComboBox), "-QualityGate", Selected(_qualityGateComboBox), "-DryRun")); });
            AddActionButton(stack, "Saude Das Distros", false, delegate { RunSingle("Saude das distros", Args("-BackupMode", "Distros", "-QualityGate", Selected(_qualityGateComboBox), "-HealthOnly")); });
            AddActionButton(stack, "Full Template", true, delegate { RunFullTemplate(); });
            stack.Children.Add(new Separator { Margin = new Thickness(0, 6, 0, 14) });

            _stopButton = Button("Parar Processo", false);
            _stopButton.IsEnabled = false;
            _stopButton.Click += delegate { StopRunningProcess(); };
            stack.Children.Add(_stopButton);

            stack.Children.Add(new TextBlock
            {
                Text = "Organizar Diretorios nao exporta distros, nao copia VHDX e nao desliga o WSL. Full Template pode desligar WSL.",
                Margin = new Thickness(0, 16, 0, 0),
                TextWrapping = TextWrapping.Wrap,
                Foreground = Brush("#64748B")
            });

            var logPanel = PanelBorder();
            logPanel.Padding = new Thickness(16);
            Grid.SetColumn(logPanel, 1);
            grid.Children.Add(logPanel);

            var logGrid = new Grid();
            logGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            logGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            logPanel.Child = logGrid;

            var logHeader = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
            Grid.SetRow(logHeader, 0);
            logGrid.Children.Add(logHeader);

            var clearButton = Button("Limpar", false);
            clearButton.Click += delegate { _logTextBox.Clear(); };
            DockPanel.SetDock(clearButton, Dock.Right);
            logHeader.Children.Add(clearButton);
            logHeader.Children.Add(new TextBlock
            {
                Text = "Log",
                FontSize = 17,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center
            });

            _logTextBox = new TextBox
            {
                FontFamily = new FontFamily("Consolas"),
                FontSize = 12,
                AcceptsReturn = true,
                AcceptsTab = true,
                IsReadOnly = true,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                TextWrapping = TextWrapping.NoWrap,
                Background = Brush("#0F172A"),
                Foreground = Brush("#E2E8F0"),
                BorderThickness = new Thickness(0),
                Padding = new Thickness(12)
            };
            Grid.SetRow(_logTextBox, 1);
            logGrid.Children.Add(_logTextBox);
        }

        private void AddFooter(Grid root)
        {
            var footer = new TextBlock
            {
                Text = "Script: " + (_scriptPath ?? "nao encontrado"),
                Margin = new Thickness(2, 12, 2, 0),
                Foreground = Brush("#64748B")
            };
            Grid.SetRow(footer, 3);
            root.Children.Add(footer);
        }

        private static void AddLabel(Grid grid, string text, int column)
        {
            var label = new TextBlock { Text = text, FontWeight = FontWeights.SemiBold };
            Grid.SetRow(label, 0);
            Grid.SetColumn(label, column);
            grid.Children.Add(label);
        }

        private void AddBrowseInput(Grid grid, TextBox input, int column, RoutedEventHandler browseHandler)
        {
            var panel = new DockPanel { Margin = new Thickness(0, 6, 14, 0) };
            Grid.SetRow(panel, 1);
            Grid.SetColumn(panel, column);
            grid.Children.Add(panel);

            var browse = Button("...", false);
            browse.Width = 38;
            browse.Margin = new Thickness(8, 0, 0, 0);
            browse.Click += browseHandler;
            DockPanel.SetDock(browse, Dock.Right);
            panel.Children.Add(browse);
            panel.Children.Add(input);
        }

        private static TextBox Input(string value)
        {
            return new TextBox
            {
                Text = value,
                MinHeight = 34,
                Padding = new Thickness(9, 6, 9, 6),
                VerticalContentAlignment = VerticalAlignment.Center,
                BorderBrush = Brush("#CBD5E1"),
                BorderThickness = new Thickness(1)
            };
        }

        private static ComboBox Combo(params string[] items)
        {
            var combo = new ComboBox
            {
                MinHeight = 34,
                Padding = new Thickness(7, 5, 7, 5),
                BorderBrush = Brush("#CBD5E1")
            };

            foreach (var item in items)
            {
                combo.Items.Add(new ComboBoxItem { Content = item });
            }

            combo.SelectedIndex = 0;
            return combo;
        }

        private void AddActionButton(StackPanel stack, string text, bool primary, RoutedEventHandler handler)
        {
            var button = Button(text, primary);
            button.Margin = new Thickness(0, 0, 0, 8);
            button.Click += handler;
            stack.Children.Add(button);
        }

        private static Button Button(string text, bool primary)
        {
            return new Button
            {
                Content = text,
                MinHeight = 38,
                Padding = new Thickness(14, 8, 14, 8),
                Background = primary ? Brush("#0F766E") : Brush("#E2E8F0"),
                Foreground = primary ? Brushes.White : Brush("#0F172A"),
                BorderBrush = primary ? Brush("#134E4A") : Brush("#CBD5E1"),
                BorderThickness = new Thickness(1),
                Cursor = System.Windows.Input.Cursors.Hand
            };
        }

        private static Border PanelBorder()
        {
            return new Border
            {
                Background = Brushes.White,
                BorderBrush = Brush("#CBD5E1"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8)
            };
        }

        private void BrowseBackupRoot(object sender, RoutedEventArgs e)
        {
            using (var dialog = new Forms.FolderBrowserDialog())
            {
                dialog.Description = "Selecione a pasta raiz do backup WSL";
                dialog.SelectedPath = _backupRootTextBox.Text;

                if (dialog.ShowDialog() == Forms.DialogResult.OK)
                {
                    _backupRootTextBox.Text = dialog.SelectedPath;
                }
            }
        }

        private void BrowseSourceVhdx(object sender, RoutedEventArgs e)
        {
            using (var dialog = new Forms.OpenFileDialog())
            {
                dialog.Title = "Selecione o WSL_Drives.vhdx";
                dialog.Filter = "VHDX (*.vhdx)|*.vhdx|Todos os arquivos (*.*)|*.*";
                dialog.FileName = _sourceVhdxTextBox.Text;

                if (dialog.ShowDialog() == Forms.DialogResult.OK)
                {
                    _sourceVhdxTextBox.Text = dialog.FileName;
                }
            }
        }

        private void RunSingle(string title, List<string> args)
        {
            if (!BeginRun(title))
            {
                return;
            }

            Task.Run(delegate
            {
                try
                {
                    var exitCode = RunPowerShell(args);
                    Dispatcher.Invoke(delegate { SetBusy(false, exitCode == 0 ? "Concluido" : "Falhou: " + exitCode); });
                }
                catch (Exception ex)
                {
                    AppendLog("ERRO: " + ex.Message);
                    Dispatcher.Invoke(delegate { SetBusy(false, "Erro"); });
                }
            });
        }

        private void RunFullTemplate()
        {
            var confirm = System.Windows.MessageBox.Show(
                "O Full Template pode desligar o WSL durante o backup real. Feche terminais e servicos dentro das distros antes de continuar.",
                "Confirmar Full Template",
                MessageBoxButton.OKCancel,
                MessageBoxImage.Warning);

            if (confirm != MessageBoxResult.OK || !BeginRun("Full Template"))
            {
                return;
            }

            Task.Run(delegate
            {
                try
                {
                    var purifyExit = RunPowerShell(Args("-BackupMode", "Distros", "-PurifyOnly", "-QualityGate", "Template"));

                    if (purifyExit != 0)
                    {
                        AppendLog("Full Template interrompido: purificacao retornou codigo " + purifyExit + ".");
                        Dispatcher.Invoke(delegate { SetBusy(false, "Falhou"); });
                        return;
                    }

                    AppendLog("");
                    AppendLog("Purificacao aprovada. Iniciando backup completo Template...");
                    var backupExit = RunPowerShell(Args("-BackupMode", "All", "-QualityGate", "Template"));
                    Dispatcher.Invoke(delegate { SetBusy(false, backupExit == 0 ? "Concluido" : "Falhou: " + backupExit); });
                }
                catch (Exception ex)
                {
                    AppendLog("ERRO: " + ex.Message);
                    Dispatcher.Invoke(delegate { SetBusy(false, "Erro"); });
                }
            });
        }

        private bool BeginRun(string title)
        {
            if (_busy)
            {
                return false;
            }

            if (string.IsNullOrWhiteSpace(_scriptPath) || !File.Exists(_scriptPath))
            {
                System.Windows.MessageBox.Show("Script PowerShell nao encontrado.", "Mega Backup WSL", MessageBoxButton.OK, MessageBoxImage.Error);
                return false;
            }

            AppendLog("");
            AppendLog("=== " + title + " ===");
            SetBusy(true, "Executando");
            return true;
        }

        private List<string> Args(params string[] args)
        {
            var result = new List<string>(args);
            result.Add("-BackupRoot");
            result.Add(_backupRootTextBox.Text.Trim());

            var sourceVhdx = _sourceVhdxTextBox.Text.Trim();
            if (!string.IsNullOrWhiteSpace(sourceVhdx))
            {
                result.Add("-SourceVhdx");
                result.Add(sourceVhdx);
            }

            return result;
        }

        private int RunPowerShell(List<string> args)
        {
            AppendLog("Comando: powershell.exe -File \"" + _scriptPath + "\" " + FormatArgs(args));

            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = _repoRoot,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };

            startInfo.Arguments =
                "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File " +
                Quote(_scriptPath) + " " +
                FormatArgs(args);

            using (var process = new Process())
            {
                process.StartInfo = startInfo;
                process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
                {
                    if (e.Data != null)
                    {
                        AppendLog(e.Data);
                    }
                };
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
                {
                    if (e.Data != null)
                    {
                        AppendLog(e.Data);
                    }
                };

                _runningProcess = process;
                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
                process.WaitForExit();
                _runningProcess = null;
                AppendLog("Codigo de saida: " + process.ExitCode);
                return process.ExitCode;
            }
        }

        private void StopRunningProcess()
        {
            try
            {
                if (_runningProcess != null && !_runningProcess.HasExited)
                {
                    _runningProcess.Kill();
                    AppendLog("Processo interrompido pelo usuario.");
                }
            }
            catch (Exception ex)
            {
                AppendLog("ERRO ao interromper: " + ex.Message);
            }
        }

        private void SetBusy(bool busy, string status)
        {
            _busy = busy;
            _statusText.Text = status;
            _stopButton.IsEnabled = busy;
        }

        private void AppendLog(string text)
        {
            Dispatcher.BeginInvoke(new Action(delegate
            {
                _logTextBox.AppendText(text + Environment.NewLine);
                _logTextBox.ScrollToEnd();
            }));
        }

        private static string Selected(ComboBox combo)
        {
            var selected = combo.SelectedItem as ComboBoxItem;
            return selected == null ? string.Empty : Convert.ToString(selected.Content);
        }

        private static string LocateRepositoryRoot()
        {
            var candidates = new[] { AppDomain.CurrentDomain.BaseDirectory, Environment.CurrentDirectory };

            foreach (var candidate in candidates)
            {
                var directory = new DirectoryInfo(candidate);

                while (directory != null)
                {
                    var scriptPath = Path.Combine(directory.FullName, "scripts", "Mega_Backup_WSL.ps1");
                    if (File.Exists(scriptPath))
                    {
                        return directory.FullName;
                    }

                    directory = directory.Parent;
                }
            }

            return string.Empty;
        }

        private static string FormatArgs(IEnumerable<string> args)
        {
            return string.Join(" ", args.Select(Quote).ToArray());
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

        private static SolidColorBrush Brush(string color)
        {
            return new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        }
    }
}
