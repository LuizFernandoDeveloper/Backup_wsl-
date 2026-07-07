using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
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
        private TabControl _mainTabs;
        private TextBlock _healthSummaryText;
        private TextBlock _healthEmptyText;
        private StackPanel _diskChartPanel;
        private StackPanel _inodeChartPanel;
        private StackPanel _riskChartPanel;
        private StackPanel _healthRowsPanel;
        private readonly Dictionary<string, DistroHealthViewModel> _healthByName =
            new Dictionary<string, DistroHealthViewModel>(StringComparer.OrdinalIgnoreCase);
        private bool _busy;

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

        [STAThread]
        public static void Main(string[] args)
        {
            var app = new Program();

            if (args.Length >= 2 && string.Equals(args[0], "--render-preview", StringComparison.OrdinalIgnoreCase))
            {
                app.RenderPreview(args[1]);
                return;
            }

            app.Run(app.CreateMainWindow());
        }

        private void RenderPreview(string outputPath)
        {
            var window = CreateMainWindow();
            LoadPreviewHealthData();

            const int width = 1120;
            const int height = 820;

            var content = window.Content as UIElement;
            if (content == null)
            {
                throw new InvalidOperationException("Conteudo da janela nao encontrado para renderizar preview.");
            }

            window.Content = null;

            var frame = new Border
            {
                Width = width,
                Height = height,
                Background = window.Background,
                Child = content
            };

            frame.Measure(new Size(width, height));
            frame.Arrange(new Rect(0, 0, width, height));
            frame.UpdateLayout();

            var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(frame);

            var fullPath = Path.GetFullPath(outputPath);
            var directory = Path.GetDirectoryName(fullPath);

            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));

            using (var stream = File.Create(fullPath))
            {
                encoder.Save(stream);
            }

            Shutdown();
        }

        private void LoadPreviewHealthData()
        {
            var ubuntu = GetHealthRow("Ubuntu");
            ubuntu.Status = "OK";
            ubuntu.RootUsedPercent = 42;
            ubuntu.InodeUsedPercent = 18;
            ubuntu.RootFree = "24,8 GB";
            ubuntu.Vhdx = "6,45 GB";

            var arch = GetHealthRow("arch-linux-current");
            arch.Status = "WARN";
            arch.RootUsedPercent = 68;
            arch.InodeUsedPercent = 31;
            arch.TemporarySockets = 2;
            arch.RootFree = "18,1 GB";
            arch.Vhdx = "7,63 GB";
            arch.AddWarning("2 socket(s) temporario(s)");

            var kali = GetHealthRow("kali-linux");
            kali.Status = "ERROR";
            kali.RootUsedPercent = 87;
            kali.InodeUsedPercent = 76;
            kali.TemporarySockets = 4;
            kali.FindErrorCount = 1;
            kali.RootFree = "9,7 GB";
            kali.Vhdx = "56,32 GB";
            kali.AddWarning("4 socket(s) temporario(s)");
            kali.AddWarning("1 erro(s) de diretorio");

            var gentoo = GetHealthRow("gentoo-current-systemd");
            gentoo.Status = "OK";
            gentoo.RootUsedPercent = 51;
            gentoo.InodeUsedPercent = 22;
            gentoo.RootFree = "21,4 GB";
            gentoo.Vhdx = "9,18 GB";

            RefreshHealthDashboard();
        }

        private Window CreateMainWindow()
        {
            _repoRoot = LocateRepositoryRoot();
            _scriptPath = Path.Combine(_repoRoot ?? string.Empty, "scripts", "Mega_Backup_WSL.ps1");

            var window = new Window
            {
                Title = "Mega Backup WSL",
                Width = 1120,
                Height = 820,
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
            AddActionButton(stack, "Saude Das Distros", false, delegate { RunHealthDiagnostics(); });
            AddActionButton(stack, "Full Template", true, delegate { RunFullTemplate(); });
            stack.Children.Add(new Separator { Margin = new Thickness(0, 6, 0, 14) });

            _stopButton = Button("Parar Processo", false);
            _stopButton.IsEnabled = false;
            _stopButton.Click += delegate { StopRunningProcess(); };
            stack.Children.Add(_stopButton);

            stack.Children.Add(new TextBlock
            {
                Text = "Organizar nao exporta nem desliga WSL. Full Template pode desligar WSL.",
                Margin = new Thickness(0, 16, 0, 0),
                TextWrapping = TextWrapping.Wrap,
                Foreground = Brush("#64748B")
            });

            _mainTabs = new TabControl
            {
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0)
            };
            Grid.SetColumn(_mainTabs, 1);
            grid.Children.Add(_mainTabs);

            _mainTabs.Items.Add(new TabItem
            {
                Header = "Saude",
                Content = CreateHealthPanel()
            });

            _mainTabs.Items.Add(new TabItem
            {
                Header = "Log",
                Content = CreateLogPanel()
            });
        }

        private Border CreateHealthPanel()
        {
            var panel = PanelBorder();
            panel.Padding = new Thickness(16);

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            panel.Child = grid;

            var header = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
            Grid.SetRow(header, 0);
            grid.Children.Add(header);

            var refreshButton = Button("Atualizar Saude", false);
            refreshButton.Click += delegate { RunHealthDiagnostics(); };
            DockPanel.SetDock(refreshButton, Dock.Right);
            header.Children.Add(refreshButton);
            header.Children.Add(new TextBlock
            {
                Text = "Saude Das Distros",
                FontSize = 17,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center
            });

            _healthSummaryText = new TextBlock
            {
                Text = "OK 0   WARN 0   ERROR 0   Total 0",
                Foreground = Brush("#475569"),
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 0, 0, 12)
            };
            Grid.SetRow(_healthSummaryText, 1);
            grid.Children.Add(_healthSummaryText);

            var scroll = new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
            };
            Grid.SetRow(scroll, 2);
            grid.Children.Add(scroll);

            var content = new StackPanel();
            scroll.Content = content;

            _healthEmptyText = new TextBlock
            {
                Text = "Sem diagnostico carregado.",
                Foreground = Brush("#64748B"),
                Margin = new Thickness(0, 8, 0, 12)
            };
            content.Children.Add(_healthEmptyText);

            content.Children.Add(SectionTitle("Uso Do Disco"));
            _diskChartPanel = ChartPanel();
            content.Children.Add(_diskChartPanel);

            content.Children.Add(SectionTitle("Uso De Inodes"));
            _inodeChartPanel = ChartPanel();
            content.Children.Add(_inodeChartPanel);

            content.Children.Add(SectionTitle("Risco Do Template"));
            _riskChartPanel = ChartPanel();
            content.Children.Add(_riskChartPanel);

            content.Children.Add(SectionTitle("Detalhe Por Distro"));
            _healthRowsPanel = new StackPanel();
            content.Children.Add(_healthRowsPanel);

            RefreshHealthDashboard();
            return panel;
        }

        private Border CreateLogPanel()
        {
            var logPanel = PanelBorder();
            logPanel.Padding = new Thickness(16);

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

            return logPanel;
        }

        private static TextBlock SectionTitle(string text)
        {
            return new TextBlock
            {
                Text = text,
                FontSize = 14,
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 14, 0, 8)
            };
        }

        private static StackPanel ChartPanel()
        {
            return new StackPanel
            {
                Margin = new Thickness(0, 0, 0, 2)
            };
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

        private void RefreshHealthDashboard()
        {
            if (_healthSummaryText == null || _diskChartPanel == null || _inodeChartPanel == null || _riskChartPanel == null || _healthRowsPanel == null)
            {
                return;
            }

            var rows = _healthByName.Values.OrderBy(row => row.Name).ToList();
            var okCount = rows.Count(row => string.Equals(row.Status, "OK", StringComparison.OrdinalIgnoreCase));
            var warnCount = rows.Count(row => string.Equals(row.Status, "WARN", StringComparison.OrdinalIgnoreCase));
            var errorCount = rows.Count(row => string.Equals(row.Status, "ERROR", StringComparison.OrdinalIgnoreCase));

            _healthSummaryText.Text =
                "OK " + okCount +
                "   WARN " + warnCount +
                "   ERROR " + errorCount +
                "   Total " + rows.Count;

            _healthEmptyText.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            _diskChartPanel.Children.Clear();
            _inodeChartPanel.Children.Clear();
            _riskChartPanel.Children.Clear();
            _healthRowsPanel.Children.Clear();

            if (rows.Count == 0)
            {
                return;
            }

            var maxRisk = Math.Max(1, rows.Max(row => row.RiskScore));

            foreach (var row in rows)
            {
                AddPercentChartRow(_diskChartPanel, row.Name, row.RootUsedPercent, PercentBrush(row.RootUsedPercent, row.Status));
                AddPercentChartRow(_inodeChartPanel, row.Name, row.InodeUsedPercent, PercentBrush(row.InodeUsedPercent, row.Status));
                AddValueChartRow(_riskChartPanel, row.Name, row.RiskScore, maxRisk, RiskBrush(row));
                _healthRowsPanel.Children.Add(CreateHealthRow(row));
            }
        }

        private void AddPercentChartRow(StackPanel panel, string name, int percent, Brush fill)
        {
            var grid = new Grid { Margin = new Thickness(0, 0, 0, 7) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(54) });

            grid.Children.Add(new TextBlock
            {
                Text = name,
                TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = Brush("#334155")
            });

            var bar = PercentBar(percent, fill);
            Grid.SetColumn(bar, 1);
            grid.Children.Add(bar);

            var value = new TextBlock
            {
                Text = ClampPercent(percent) + "%",
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = Brush("#475569"),
                FontWeight = FontWeights.SemiBold
            };
            Grid.SetColumn(value, 2);
            grid.Children.Add(value);

            panel.Children.Add(grid);
        }

        private void AddValueChartRow(StackPanel panel, string name, int value, int maxValue, Brush fill)
        {
            var grid = new Grid { Margin = new Thickness(0, 0, 0, 7) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(54) });

            grid.Children.Add(new TextBlock
            {
                Text = name,
                TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = Brush("#334155")
            });

            var percent = maxValue <= 0 ? 0 : (int)Math.Round((value * 100.0) / maxValue);
            var bar = PercentBar(percent, fill);
            Grid.SetColumn(bar, 1);
            grid.Children.Add(bar);

            var valueText = new TextBlock
            {
                Text = value.ToString(),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = Brush("#475569"),
                FontWeight = FontWeights.SemiBold
            };
            Grid.SetColumn(valueText, 2);
            grid.Children.Add(valueText);

            panel.Children.Add(grid);
        }

        private static Border PercentBar(int percent, Brush fill)
        {
            var value = ClampPercent(percent);
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.0, value), GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(0.1, 100 - value), GridUnitType.Star) });

            if (value > 0)
            {
                var filled = new Border
                {
                    Background = fill,
                    CornerRadius = new CornerRadius(5)
                };
                Grid.SetColumn(filled, 0);
                grid.Children.Add(filled);
            }

            return new Border
            {
                Height = 12,
                Background = Brush("#E2E8F0"),
                CornerRadius = new CornerRadius(5),
                Child = grid,
                VerticalAlignment = VerticalAlignment.Center
            };
        }

        private Border CreateHealthRow(DistroHealthViewModel row)
        {
            var border = new Border
            {
                Background = Brush("#F8FAFC"),
                BorderBrush = Brush("#CBD5E1"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(12),
                Margin = new Thickness(0, 0, 0, 8)
            };

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(92) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.8, GridUnitType.Star) });
            border.Child = grid;

            grid.Children.Add(new TextBlock
            {
                Text = row.Name,
                FontWeight = FontWeights.SemiBold,
                TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center
            });

            var status = StatusPill(row.Status);
            Grid.SetColumn(status, 1);
            grid.Children.Add(status);

            var disk = SmallMetric("/", row.RootUsedPercent + "% usado");
            Grid.SetColumn(disk, 2);
            grid.Children.Add(disk);

            var inode = SmallMetric("inodes", row.InodeUsedPercent + "%");
            Grid.SetColumn(inode, 3);
            grid.Children.Add(inode);

            var warnings = new TextBlock
            {
                Text = row.WarningSummary,
                TextWrapping = TextWrapping.Wrap,
                Foreground = row.RiskScore == 0 ? Brush("#64748B") : Brush("#7F1D1D"),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(warnings, 4);
            grid.Children.Add(warnings);

            return border;
        }

        private static StackPanel SmallMetric(string label, string value)
        {
            var panel = new StackPanel
            {
                Margin = new Thickness(10, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center
            };

            panel.Children.Add(new TextBlock
            {
                Text = label,
                FontSize = 11,
                Foreground = Brush("#64748B")
            });

            panel.Children.Add(new TextBlock
            {
                Text = value,
                FontWeight = FontWeights.SemiBold,
                Foreground = Brush("#0F172A")
            });

            return panel;
        }

        private static Border StatusPill(string status)
        {
            return new Border
            {
                Background = StatusBackgroundBrush(status),
                BorderBrush = StatusBorderBrush(status),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(9, 4, 9, 4),
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Center,
                Child = new TextBlock
                {
                    Text = status,
                    Foreground = StatusTextBrush(status),
                    FontWeight = FontWeights.SemiBold,
                    FontSize = 12
                }
            };
        }

        private static Brush PercentBrush(int percent, string status)
        {
            if (string.Equals(status, "ERROR", StringComparison.OrdinalIgnoreCase) || percent >= 90)
            {
                return Brush("#DC2626");
            }

            if (string.Equals(status, "WARN", StringComparison.OrdinalIgnoreCase) || percent >= 75)
            {
                return Brush("#D97706");
            }

            return Brush("#0F766E");
        }

        private static Brush RiskBrush(DistroHealthViewModel row)
        {
            if (string.Equals(row.Status, "ERROR", StringComparison.OrdinalIgnoreCase) || row.RiskScore >= 8)
            {
                return Brush("#DC2626");
            }

            if (string.Equals(row.Status, "WARN", StringComparison.OrdinalIgnoreCase) || row.RiskScore > 0)
            {
                return Brush("#D97706");
            }

            return Brush("#0F766E");
        }

        private static Brush StatusBackgroundBrush(string status)
        {
            if (string.Equals(status, "ERROR", StringComparison.OrdinalIgnoreCase))
            {
                return Brush("#FEF2F2");
            }

            if (string.Equals(status, "WARN", StringComparison.OrdinalIgnoreCase))
            {
                return Brush("#FFFBEB");
            }

            return Brush("#ECFDF5");
        }

        private static Brush StatusBorderBrush(string status)
        {
            if (string.Equals(status, "ERROR", StringComparison.OrdinalIgnoreCase))
            {
                return Brush("#FCA5A5");
            }

            if (string.Equals(status, "WARN", StringComparison.OrdinalIgnoreCase))
            {
                return Brush("#FCD34D");
            }

            return Brush("#99F6E4");
        }

        private static Brush StatusTextBrush(string status)
        {
            if (string.Equals(status, "ERROR", StringComparison.OrdinalIgnoreCase))
            {
                return Brush("#991B1B");
            }

            if (string.Equals(status, "WARN", StringComparison.OrdinalIgnoreCase))
            {
                return Brush("#92400E");
            }

            return Brush("#134E4A");
        }

        private static int ClampPercent(int value)
        {
            return Math.Max(0, Math.Min(100, value));
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

        private void RunHealthDiagnostics()
        {
            if (_busy)
            {
                return;
            }

            ResetHealthDashboard();

            if (_mainTabs != null)
            {
                _mainTabs.SelectedIndex = 0;
            }

            RunSingle("Saude das distros", Args("-BackupMode", "Distros", "-QualityGate", Selected(_qualityGateComboBox), "-HealthOnly"));
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

            ResetHealthDashboard();

            if (_mainTabs != null)
            {
                _mainTabs.SelectedIndex = 0;
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
                ParseHealthLine(text);
                _logTextBox.AppendText(text + Environment.NewLine);
                _logTextBox.ScrollToEnd();
            }));
        }

        private void ResetHealthDashboard()
        {
            _healthByName.Clear();
            RefreshHealthDashboard();
        }

        private void ParseHealthLine(string text)
        {
            if (string.IsNullOrWhiteSpace(text))
            {
                return;
            }

            var healthMatch = HealthLineRegex.Match(text);
            if (healthMatch.Success)
            {
                var health = GetHealthRow(healthMatch.Groups["name"].Value);
                health.Status = healthMatch.Groups["status"].Value.Trim();
                health.RootUsedPercent = ReadInt(healthMatch.Groups["root"].Value);
                health.RootFree = healthMatch.Groups["free"].Value.Trim();
                health.InodeUsedPercent = ReadInt(healthMatch.Groups["inode"].Value);
                health.TemporarySockets = ReadLong(healthMatch.Groups["sockets"].Value);
                health.Vhdx = healthMatch.Groups["vhdx"].Value.Trim();
                RefreshHealthDashboard();
                return;
            }

            var warningMatch = WarningLineRegex.Match(text);
            if (warningMatch.Success)
            {
                var health = GetHealthRow(warningMatch.Groups["name"].Value);
                var warnings = warningMatch.Groups["warnings"].Value.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries);

                foreach (var warning in warnings)
                {
                    health.AddWarning(warning.Trim());
                }

                RefreshHealthDashboard();
                return;
            }

            var deepMatch = DeepHealthLineRegex.Match(text);
            if (deepMatch.Success)
            {
                var health = GetHealthRow(deepMatch.Groups["name"].Value);
                health.AllSockets = ReadLong(deepMatch.Groups["sockets"].Value);
                health.BrokenLinks = ReadLong(deepMatch.Groups["links"].Value);
                health.RootReadOnly = ReadBool(deepMatch.Groups["readonly"].Value);
                health.TmpWritable = ReadBool(deepMatch.Groups["tmp"].Value);
                health.HomeWritable = ReadBool(deepMatch.Groups["home"].Value);
                health.FindErrorCount = ReadLong(deepMatch.Groups["find"].Value);

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

                RefreshHealthDashboard();
                return;
            }

            var directoryMatch = DirectoryIssueLineRegex.Match(text);
            if (directoryMatch.Success)
            {
                GetHealthRow(directoryMatch.Groups["name"].Value).AddWarning("erros de diretorio");
                RefreshHealthDashboard();
                return;
            }

            var dmesgMatch = DmesgIssueLineRegex.Match(text);
            if (dmesgMatch.Success)
            {
                GetHealthRow(dmesgMatch.Groups["name"].Value).AddWarning("dmesg com sinal grave");
                RefreshHealthDashboard();
            }
        }

        private DistroHealthViewModel GetHealthRow(string name)
        {
            var safeName = string.IsNullOrWhiteSpace(name) ? "Desconhecida" : name.Trim();
            DistroHealthViewModel health;

            if (!_healthByName.TryGetValue(safeName, out health))
            {
                health = new DistroHealthViewModel(safeName);
                _healthByName.Add(safeName, health);
            }

            return health;
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

        private sealed class DistroHealthViewModel
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
}
