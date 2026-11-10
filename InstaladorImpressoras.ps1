<#
==============================================================================
 INSTALADOR AUTOMATICO DE IMPRESSORAS - TI PREFEITURA
==============================================================================
 Identificacao e instalacao automatica de impressoras:
   - Descoberta rapida em segundo plano (Rede Local e portas USB)
   - Seletor e campo editavel para faixa de IP da rede
   - Interface fluida com barra de carregamento animada
   - Opcao para personalizar o nome da impressora no Windows
   - Download automatico de drivers se nao encontrados localmente
   - Impressao automatica de pagina de teste
   - Suporte a configuracao manual por IP
==============================================================================
#>

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ------------------------------------------------------------------------
# 1. VERIFICA E SOLICITA ELEVACAO (ADMINISTRADOR)
# ------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        if ($PSCommandPath) {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
            exit
        } else {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"& '$PSScriptRoot\InstaladorImpressoras.ps1'`"" -Verb RunAs
            exit
        }
    } catch {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            "Este instalador precisa de privilegios de Administrador para instalar drivers e impressoras.`n`nPor favor, execute como Administrador.",
            "Permissao Necessaria", "OK", "Warning") | Out-Null
        exit
    }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ------------------------------------------------------------------------
# 2. LOCALIZACAO DA PASTA DE DRIVERS E DLL DE DESCOBERTA
# ------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = [System.AppDomain]::CurrentDomain.BaseDirectory }
if (-not $ScriptDir) { $ScriptDir = "C:\Impressora IT (Útil)" }

$candidatos = @(
    (Join-Path $ScriptDir "Drivers"),
    "C:\Impressora IT (Útil)\Drivers",
    "C:\ImpressorasIT\Drivers"
)

$DriversRoot = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $DriversRoot) { $DriversRoot = Join-Path $ScriptDir "Drivers" }

# Carrega a biblioteca de escaneamento rapido de rede e USB
$dllPath = Join-Path (Join-Path $ScriptDir "src") "FastPrinterDiscovery.dll"
$csPath  = Join-Path (Join-Path $ScriptDir "src") "FastPrinterDiscovery.cs"

if (Test-Path $csPath) {
    try { Add-Type -Path $csPath -ErrorAction Stop }
    catch {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Nao foi possivel compilar o modulo de descoberta de impressoras:`n$($_.Exception.Message)", "Erro no modulo de descoberta", "OK", "Error") | Out-Null
        exit
    }
} elseif (Test-Path $dllPath) {
    Add-Type -Path $dllPath -ErrorAction Stop
}

# ------------------------------------------------------------------------
# 3. CATALOGO DE IMPRESSORAS E DRIVERS
# ------------------------------------------------------------------------
$Impressoras = [ordered]@{
    "Canon" = [ordered]@{
        "imageRUNNER 1643iF" = @{
            Pasta        = "iR1643iF"
            DriverNames  = @("Canon Generic Plus PCL6")
            Installer    = ""
            SilentArgs   = ""
            Descricao    = "Multifuncional Laser Monocromatica A4 (PCL6)"
            DownloadUrl  = "https://www.usa.canon.com/support/p/imagerunner-1643if"
        }
        "GX7010 / GX7000" = @{
            Pasta        = "GX7000"
            DriverNames  = @("Canon G7000 series", "Canon GX7000 series", "Canon GX7010 series")
            Installer    = "Setup.exe"
            SilentArgs   = "/SILENT"
            Descricao    = "Multifuncional Tanque de Tinta Colorida"
            DownloadUrl  = "https://www.canon.com.br/support"
        }
    }
    "Brother" = [ordered]@{
        "DCP-L5652DN" = @{
            Pasta        = "DCPL5652DN"
            DriverNames  = @("Brother DCP-L5652DN series", "Brother DCP-L5652DN", "Brother DCP-L5650DN series")
            Installer    = "DCP-L5652DN_full_install.exe"
            SilentArgs   = "/S"
            Descricao    = "Multifuncional Laser Monocromatica Robusta"
            DownloadUrl  = "https://download.brother.com/welcome/dlf102737/Y15C_C1-hostm-120.EXE"
        }
    }
    "Epson" = [ordered]@{
        "EcoTank L6490" = @{
            Pasta        = "L6490"
            DriverNames  = @("EPSON L6490 Series", "EPSON L6490 series")
            Installer    = "Setup.exe"
            SilentArgs   = "/S /qn"
            Descricao    = "Multifuncional Tanque de Tinta Colorida com ADF"
            DownloadUrl  = "https://ftp.epson.com/latin/drivers/inkjet/L6490_X64_38005_LA.exe"
            DownloadUrlX86 = "https://ftp.epson.com/latin/drivers/inkjet/L6490_X86_38005_LA.exe"
        }
    }
}

# ------------------------------------------------------------------------
# 4. FUNCOES AUXILIARES
# ------------------------------------------------------------------------
function ObterSubredesLocais {
    $candidatos = @()
    $metricasRota = @{}

    # A tabela de rotas identifica qual interface o Windows usa como rota padrao.
    try {
        foreach ($linha in (& route.exe print -4 2>$null)) {
            if ($linha -match '^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d{1,3}(?:\.\d{1,3}){3})\s+(\d{1,3}(?:\.\d{1,3}){3})\s+(\d+)\s*$') {
                $interfaceIp = $matches[2]
                $metricasRota[$interfaceIp] = [int]$matches[3]
            }
        }
    } catch {}

    try {
        $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' }

        foreach ($nic in $interfaces) {
            $props = $nic.GetIPProperties()
            $temGateway = @($props.GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -ne '0.0.0.0' }).Count -gt 0

            foreach ($uni in $props.UnicastAddresses) {
                if ($uni.Address.AddressFamily -ne 'InterNetwork') { continue }
                $ip = $uni.Address.ToString()
                if ($ip -like '169.254.*' -or $ip -like '127.*') { continue }

                $ipBytes = $uni.Address.GetAddressBytes()
                $maskBytes = $uni.IPv4Mask.GetAddressBytes()
                $prefix = 0
                $contiguous = $true
                $sawZero = $false
                foreach ($maskByte in $maskBytes) {
                    for ($bit = 7; $bit -ge 0; $bit--) {
                        $isSet = (($maskByte -band (1 -shl $bit)) -ne 0)
                        if ($isSet -and $sawZero) { $contiguous = $false }
                        if ($isSet) { $prefix++ } else { $sawZero = $true }
                    }
                }
                if (-not $contiguous -or $prefix -lt 1) { continue }

                $networkBytes = @()
                for ($i = 0; $i -lt 4; $i++) { $networkBytes += ($ipBytes[$i] -band $maskBytes[$i]) }
                $networkIp = ($networkBytes -join '.')
                $metric = 100000
                if ($metricasRota.ContainsKey($ip)) { $metric = $metricasRota[$ip] }
                $candidatos += [pscustomobject]@{
                    Faixa = "$networkIp/$prefix"
                    IP = $ip
                    Metrica = $metric
                    TemGateway = $temGateway
                }
            }
        }
    } catch {}

    $resultado = @()
    foreach ($item in ($candidatos | Sort-Object @{Expression='Metrica'}, @{Expression={ if ($_.TemGateway) { 0 } else { 1 } }})) {
        if ($resultado -notcontains $item.Faixa) { $resultado += $item.Faixa }
    }
    return $resultado
}

function NormalizarFaixa($entrada) {
    if (-not $entrada) { return "" }
    $txt = $entrada.Trim()
    if ($txt -match '^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$') { return $txt }
    if ($txt -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.$') { return $txt }
    if ($txt -match '^\d{1,3}\.\d{1,3}\.\d{1,3}$') { return ($txt + ".") }
    if ($txt -match '^(\d{1,3}\.){3}\d{1,3}$') { return $txt }
    return $txt
}

function ObterPastaModelo($m, $mod) {
    if (-not $m -or -not $mod) { return $null }
    $cfg = $Impressoras[$m][$mod]
    if (-not $cfg) { return $null }
    $caminhos = @(
        (Join-Path (Join-Path $DriversRoot $m) $cfg.Pasta),
        (Join-Path $DriversRoot $cfg.Pasta),
        (Join-Path "C:\ImpressorasIT\Drivers\$m" $cfg.Pasta)
    )
    foreach ($c in $caminhos) {
        if (Test-Path $c) { return $c }
    }
    return (Join-Path (Join-Path $DriversRoot $m) $cfg.Pasta)
}

function VerificarDriverPronto($m, $mod) {
    $pasta = ObterPastaModelo $m $mod
    if (-not $pasta -or -not (Test-Path $pasta)) { return $false }
    $infs = Get-ChildItem -Path $pasta -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    return ($infs.Count -gt 0)
}

# ------------------------------------------------------------------------
# 5. INTERFACE GRAFICA (WPF / XAML)
# ------------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Instalador Inteligente de Impressoras - TI Prefeitura" Height="580" Width="480"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#F8FAFC" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Height" Value="40"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>
    </Window.Resources>
    
    <Grid Margin="20">

        <!-- PAINEL 1: DESCOBERTA AUTOMATICA -->
        <StackPanel x:Name="painelDescoberta">
            <TextBlock Text="DESCOBERTA AUTOMATICA" Foreground="#64748B" FontSize="11" FontWeight="Bold"/>
            <TextBlock Text="Localizar Impressoras" FontSize="20" FontWeight="Bold" Foreground="#0F172A" Margin="0,2,0,4"/>
            <TextBlock Text="Identifica impressoras na rede local e portas USB:" FontSize="13" Foreground="#475569" Margin="0,0,0,10"/>

            <!-- Seletor e Campo Editavel de Faixa de IP -->
            <Border Background="#F1F5F9" CornerRadius="6" Padding="10" Margin="0,0,0,10" BorderBrush="#E2E8F0" BorderThickness="1">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="Faixa de IP da rede:" VerticalAlignment="Center" FontWeight="SemiBold" FontSize="13" Foreground="#1E293B" Margin="0,0,10,0"/>
                    <ComboBox x:Name="cbFaixaIP" Grid.Column="1" Height="32" FontSize="14" IsEditable="True" ToolTip="Selecione ou digite a faixa da sua rede (ex: 10.0.0. ou 192.168.1.)"/>
                </Grid>
            </Border>

            <Button x:Name="btnBuscar" Content="Procurar Impressoras na Rede e USB" Height="42" FontWeight="Bold" FontSize="14" Background="#2563EB" Foreground="White" BorderThickness="0" Margin="0,0,0,10"/>

            <TextBlock x:Name="txtStatusBusca" Text="Pronto para iniciar a busca." FontSize="12" Foreground="#475569" Margin="2,0,0,6"/>
            <ProgressBar x:Name="barraBusca" Height="10" IsIndeterminate="False" Visibility="Hidden" Margin="0,0,0,10"/>

            <TextBlock Text="Impressoras Encontradas:" FontSize="12" FontWeight="SemiBold" Foreground="#334155" Margin="0,2,0,6"/>
            <ListBox x:Name="lstImpressoras" Height="170" Background="#FFFFFF" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,0,10" SelectionMode="Single"/>

            <Button x:Name="btnAvancarDescoberta" Content="Configurar Impressora Selecionada &gt;" Height="40" FontWeight="Bold" Background="#0F172A" Foreground="White" BorderThickness="0" IsEnabled="False" Margin="0,0,0,6"/>
            <Button x:Name="btnIrManual" Content="Nao encontrou? Inserir IP ou Modelo Manualmente" Background="Transparent" BorderThickness="0" Foreground="#2563EB" Height="26" FontSize="12"/>
        </StackPanel>

        <!-- PAINEL 2: CONFIGURACAO / PERSONALIZACAO DO NOME -->
        <StackPanel x:Name="painelConfiguracao" Visibility="Collapsed">
            <TextBlock Text="ETAPA 2 DE 3" Foreground="#64748B" FontSize="11" FontWeight="Bold"/>
            <TextBlock Text="Personalizar e Confirmar" FontSize="20" FontWeight="Bold" Foreground="#0F172A" Margin="0,2,0,14"/>

            <Border Background="#F1F5F9" CornerRadius="6" Padding="12" Margin="0,0,0,14" BorderBrush="#E2E8F0" BorderThickness="1">
                <StackPanel>
                    <TextBlock x:Name="lblResumoModelo" Text="Modelo: ..." FontSize="14" FontWeight="Bold" Foreground="#1E293B"/>
                    <TextBlock x:Name="lblResumoConexao" Text="Conexao: ..." FontSize="12" Foreground="#475569" Margin="0,2,0,0"/>
                    <TextBlock x:Name="lblResumoDriver" Text="Driver: ..." FontSize="12" Foreground="#16A34A" FontWeight="SemiBold" Margin="0,2,0,0"/>
                </StackPanel>
            </Border>

            <TextBlock Text="Nome da Impressora no Windows:" FontSize="13" FontWeight="SemiBold" Foreground="#1E293B" Margin="0,0,0,4"/>
            <TextBox x:Name="txtNomePersonalizado" Height="36" FontSize="14" VerticalContentAlignment="Center" Padding="8,0" Background="#FFFFFF" BorderBrush="#CBD5E1" Margin="0,0,0,4"/>
            <TextBlock Text="Voce pode manter o nome acima ou personalizar (ex: Canon 1643 - Gabinete, Epson - Recepcao)." FontSize="11" Foreground="#64748B" TextWrapping="Wrap" Margin="0,0,0,14"/>

            <CheckBox x:Name="chkTeste" Content="Imprimir pagina de teste ao concluir a instalacao" IsChecked="True" FontSize="13" Margin="0,0,0,8"/>
            <CheckBox x:Name="chkDownload" Content="Baixar driver oficial da internet caso nao esteja no PC" IsChecked="True" FontSize="13" Margin="0,0,0,18"/>

            <StackPanel Orientation="Horizontal">
                <Button x:Name="btnVoltarConfig" Content="&lt; Voltar" Width="90" Height="42" Margin="0,0,10,0"/>
                <Button x:Name="btnInstalarConfirmado" Content="INSTALAR AGORA" Width="220" Height="42" FontWeight="Bold" Background="#16A34A" Foreground="White" BorderThickness="0"/>
            </StackPanel>
        </StackPanel>

        <!-- PAINEL 3: CONFIGURACAO MANUAL -->
        <StackPanel x:Name="painelManual" Visibility="Collapsed">
            <TextBlock Text="MODO MANUAL" Foreground="#64748B" FontSize="11" FontWeight="Bold"/>
            <TextBlock Text="Selecao Manual" FontSize="20" FontWeight="Bold" Foreground="#0F172A" Margin="0,2,0,14"/>

            <TextBlock Text="Selecione a marca:" FontSize="12" Foreground="#475569" Margin="0,0,0,4"/>
            <ComboBox x:Name="cbMarcaManual" Height="34" FontSize="14" Margin="0,0,0,10"/>

            <TextBlock Text="Selecione o modelo:" FontSize="12" Foreground="#475569" Margin="0,0,0,4"/>
            <ComboBox x:Name="cbModeloManual" Height="34" FontSize="14" Margin="0,0,0,10"/>

            <TextBlock Text="Endereco IP da impressora (ou porta USB001):" FontSize="12" Foreground="#475569" Margin="0,0,0,4"/>
            <TextBox x:Name="txtIPManual" Height="34" FontSize="14" VerticalContentAlignment="Center" Padding="8,0" Margin="0,0,0,4"/>
            <TextBlock Text="Exemplo: 192.168.1.150 ou 10.0.0.50" FontSize="11" Foreground="#94A3B8" Margin="0,0,0,14"/>

            <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                <Button x:Name="btnVoltarManual" Content="&lt; Voltar a Busca" Width="120" Height="40" Margin="0,0,10,0"/>
                <Button x:Name="btnAvancarManual" Content="Avancar &gt;" Width="120" Height="40" FontWeight="Bold" Background="#2563EB" Foreground="White" BorderThickness="0"/>
            </StackPanel>
        </StackPanel>

        <!-- PAINEL 4: PROGRESSO DA INSTALACAO -->
        <StackPanel x:Name="painelProgresso" Visibility="Collapsed" VerticalAlignment="Center">
            <TextBlock x:Name="tituloProgresso" Text="Instalando..." FontSize="18" FontWeight="Bold" HorizontalAlignment="Center" Foreground="#0F172A"/>
            <TextBlock x:Name="txtPercentual" Text="0%" FontSize="38" FontWeight="Bold" HorizontalAlignment="Center" Foreground="#2563EB" Margin="0,6,0,6"/>
            <ProgressBar x:Name="barra" Height="16" Minimum="0" Maximum="100" Margin="0,0,0,12"/>
            <TextBlock x:Name="txtEtapa" Text="Iniciando processo..." FontSize="12" Foreground="#475569" TextWrapping="Wrap" TextAlignment="Center" Margin="0,0,0,18"/>
            
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                <Button x:Name="btnNovaInstalacao" Content="Instalar Outra" Width="130" Height="38" Margin="0,0,10,0" Visibility="Collapsed"/>
                <Button x:Name="btnFechar" Content="Fechar" Width="110" Height="38" Background="#0F172A" Foreground="White" BorderThickness="0" Visibility="Collapsed"/>
            </StackPanel>
        </StackPanel>

    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Elementos da UI
$painelDescoberta     = $window.FindName("painelDescoberta")
$cbFaixaIP            = $window.FindName("cbFaixaIP")
$btnBuscar            = $window.FindName("btnBuscar")
$txtStatusBusca       = $window.FindName("txtStatusBusca")
$barraBusca           = $window.FindName("barraBusca")
$lstImpressoras       = $window.FindName("lstImpressoras")
$btnAvancarDescoberta = $window.FindName("btnAvancarDescoberta")
$btnIrManual          = $window.FindName("btnIrManual")

$painelConfiguracao   = $window.FindName("painelConfiguracao")
$lblResumoModelo      = $window.FindName("lblResumoModelo")
$lblResumoConexao     = $window.FindName("lblResumoConexao")
$lblResumoDriver      = $window.FindName("lblResumoDriver")
$txtNomePersonalizado = $window.FindName("txtNomePersonalizado")
$chkTeste             = $window.FindName("chkTeste")
$chkDownload          = $window.FindName("chkDownload")
$btnVoltarConfig      = $window.FindName("btnVoltarConfig")
$btnInstalarConfirmado = $window.FindName("btnInstalarConfirmado")

$painelManual         = $window.FindName("painelManual")
$cbMarcaManual        = $window.FindName("cbMarcaManual")
$cbModeloManual       = $window.FindName("cbModeloManual")
$txtIPManual          = $window.FindName("txtIPManual")
$btnVoltarManual      = $window.FindName("btnVoltarManual")
$btnAvancarManual     = $window.FindName("btnAvancarManual")

$painelProgresso      = $window.FindName("painelProgresso")
$tituloProgresso      = $window.FindName("tituloProgresso")
$txtPercentual        = $window.FindName("txtPercentual")
$barra                = $window.FindName("barra")
$txtEtapa             = $window.FindName("txtEtapa")
$btnNovaInstalacao    = $window.FindName("btnNovaInstalacao")
$btnFechar            = $window.FindName("btnFechar")

# Estado de execucao
$state = @{
    ImpressorasEncontradas = @()
    DispositivoSelecionado = $null
    Marca                  = $null
    Modelo                 = $null
    Tipo                   = "Rede"
    Endereco               = ""
    NomePersonalizado      = ""
}

function MostrarPainel($painel) {
    foreach ($p in @($painelDescoberta, $painelConfiguracao, $painelManual, $painelProgresso)) {
        $p.Visibility = "Collapsed"
    }
    $painel.Visibility = "Visible"
}

function AtualizarProgresso([int]$valor, [string]$mensagem) {
    $barra.Value = $valor
    $txtPercentual.Text = "$valor%"
    $txtEtapa.Text = $mensagem
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

# Prioriza a sub-rede da interface escolhida pelo Windows para a rota padrao.
$subredesDetectadas = @(ObterSubredesLocais)
foreach ($s in $subredesDetectadas) { $cbFaixaIP.Items.Add($s) | Out-Null }
foreach ($comum in @("10.0.0.", "192.168.1.", "192.168.0.", "172.16.0.")) {
    if ($cbFaixaIP.Items -notcontains $comum) { $cbFaixaIP.Items.Add($comum) | Out-Null }
}
if ($subredesDetectadas.Count -gt 0) {
    $cbFaixaIP.SelectedIndex = 0
} else {
    $cbFaixaIP.SelectedIndex = -1
    $cbFaixaIP.Text = ""
}

# Preenche ComboBoxes Manuais
foreach ($m in $Impressoras.Keys) {
    $cbMarcaManual.Items.Add($m) | Out-Null
}

$cbMarcaManual.Add_SelectionChanged({
    $cbModeloManual.Items.Clear()
    $selM = $cbMarcaManual.SelectedItem
    if ($selM -and $Impressoras.Contains($selM)) {
        foreach ($mod in $Impressoras[$selM].Keys) {
            $cbModeloManual.Items.Add($mod) | Out-Null
        }
        if ($cbModeloManual.Items.Count -gt 0) { $cbModeloManual.SelectedIndex = 0 }
    }
})

# ------------------------------------------------------------------------
# 6. DESCOBERTA ASSINCRONA (REDE E USB) - COM FAIXA EDITAVEL
# ------------------------------------------------------------------------
$script:scanTimer = $null
$script:scanStartTime = $null
$script:scanTask = $null

$iniciarBusca = {
    # Obtem a faixa de IP selecionada ou digitada pelo usuario
    $faixaRaw = $cbFaixaIP.Text
    if ([string]::IsNullOrWhiteSpace($faixaRaw) -and $cbFaixaIP.SelectedItem) { $faixaRaw = [string]$cbFaixaIP.SelectedItem }
    $faixaAlvo = NormalizarFaixa $faixaRaw

    $btnBuscar.IsEnabled = $false
    $barraBusca.Visibility = "Visible"
    $barraBusca.IsIndeterminate = $true
    if ($faixaAlvo) {
        $txtStatusBusca.Text = "Procurando na rede detectada ($faixaAlvo) e portas USB..."
    } else {
        $txtStatusBusca.Text = "Rede nao detectada; verificando portas USB..."
    }
    $lstImpressoras.Items.Clear()
    $btnAvancarDescoberta.IsEnabled = $false

    $subList = New-Object 'System.Collections.Generic.List[string]'
    if ($faixaAlvo) { $subList.Add($faixaAlvo) }

    $script:scanStartTime = [System.DateTime]::Now
    $script:scanTask = [FastPrinterDiscovery]::ScanAllAsync($subList, 250)

    $script:scanTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:scanTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $script:scanTimer.Add_Tick({
        $segundos = [int]([System.DateTime]::Now - $script:scanStartTime).TotalSeconds
        $txtStatusBusca.Text = "Escaneando faixa $($faixaAlvo) e portas USB... ($($segundos)s)"

        if ($script:scanTask.IsCompleted) {
            $script:scanTimer.Stop()
            $barraBusca.IsIndeterminate = $false
            $barraBusca.Visibility = "Hidden"
            $btnBuscar.IsEnabled = $true

            $achadas = @()
            try { $achadas = $script:scanTask.Result } catch {}
            $state.ImpressorasEncontradas = $achadas

            if (-not $achadas -or $achadas.Count -eq 0) {
                $txtStatusBusca.Text = "Nenhuma impressora encontrada na faixa $($faixaAlvo) ou USB."
                $itemAviso = New-Object System.Windows.Controls.ListBoxItem
                $itemAviso.Content = "Nenhuma impressora encontrada. Verifique a faixa de IP acima ou clique em 'Inserir IP Manualmente'."
                $itemAviso.IsEnabled = $false
                $lstImpressoras.Items.Add($itemAviso) | Out-Null
            } else {
                $txtStatusBusca.Text = "Sucesso! Foram encontradas $($achadas.Count) impressora(s)."
                foreach ($p in $achadas) {
                    $lbi = New-Object System.Windows.Controls.ListBoxItem
                    $sp = New-Object System.Windows.Controls.StackPanel
                    $sp.Margin = "4"

                    $tb1 = New-Object System.Windows.Controls.TextBlock
                    $tb1.Text = $p.DisplayTitle
                    $tb1.FontWeight = "Bold"
                    $tb1.FontSize = 13

                    $tb2 = New-Object System.Windows.Controls.TextBlock
                    $tb2.Text = $p.DisplaySubtitle
                    $tb2.FontSize = 11
                    $tb2.Foreground = "#64748B"

                    $sp.Children.Add($tb1) | Out-Null
                    $sp.Children.Add($tb2) | Out-Null
                    $lbi.Content = $sp
                    $lbi.Tag = $p
                    $lstImpressoras.Items.Add($lbi) | Out-Null
                }
            }
        }
    })
    $script:scanTimer.Start()
}

$btnBuscar.Add_Click($iniciarBusca)

$lstImpressoras.Add_SelectionChanged({
    if ($lstImpressoras.SelectedItem -and $lstImpressoras.SelectedItem.Tag) {
        $btnAvancarDescoberta.IsEnabled = $true
    } else {
        $btnAvancarDescoberta.IsEnabled = $false
    }
})

# Avanca da Descoberta para Configuracao
$btnAvancarDescoberta.Add_Click({
    $sel = $lstImpressoras.SelectedItem
    if (-not $sel -or -not $sel.Tag) { return }

    $p = $sel.Tag
    $modeloDisponivel = $false
    if ($Impressoras.Contains($p.Brand) -and $Impressoras[$p.Brand].Contains($p.Model)) { $modeloDisponivel = $true }
    if (-not $modeloDisponivel) {
        $txtIPManual.Text = $p.IP
        $cbModeloManual.Items.Clear()
        $cbMarcaManual.SelectedIndex = -1
        if ($Impressoras.Contains($p.Brand)) { $cbMarcaManual.SelectedItem = $p.Brand }
        [System.Windows.MessageBox]::Show("Impressora detectada em $($p.IP). Selecione o modelo correto para continuar.", "Identificacao manual", "OK", "Information") | Out-Null
        MostrarPainel $painelManual
        return
    }
    $state.DispositivoSelecionado = $p
    $state.Marca    = $p.Brand
    $state.Modelo   = $p.Model
    $state.Tipo     = $p.Type
    $state.Endereco = if ($p.Type -eq "USB") { "USB001" } else { $p.IP }

    $lblResumoModelo.Text  = "Marca e Modelo: $($p.Brand) $($p.Model)"
    $lblResumoConexao.Text = if ($p.Type -eq "USB") { "Conexao: Cabo USB Conectado" } else { "Conexao: Rede IP ($($p.IP))" }

    $driverPronto = VerificarDriverPronto $p.Brand $p.Model
    if ($driverPronto) {
        $lblResumoDriver.Text = "Driver: Arquivos prontos no computador"
        $lblResumoDriver.Foreground = "#16A34A"
    } else {
        $lblResumoDriver.Text = "Driver: Sera baixado automaticamente da internet"
        $lblResumoDriver.Foreground = "#2563EB"
    }

    $sugestaoNome = "$($p.Brand) $($p.Model)"
    if ($p.Type -ne "USB" -and $p.IP) {
        $sugestaoNome = "$($p.Brand) $($p.Model) ($($p.IP))"
    }
    $txtNomePersonalizado.Text = $sugestaoNome

    MostrarPainel $painelConfiguracao
})

$btnIrManual.Add_Click({
    if ($cbMarcaManual.Items.Count -gt 0) { $cbMarcaManual.SelectedIndex = 0 }
    MostrarPainel $painelManual
})

$btnVoltarConfig.Add_Click({
    MostrarPainel $painelDescoberta
})

$btnVoltarManual.Add_Click({
    MostrarPainel $painelDescoberta
})

# Avanca do Manual para Configuracao
$btnAvancarManual.Add_Click({
    $m = $cbMarcaManual.SelectedItem
    $mod = $cbModeloManual.SelectedItem
    $ip = $txtIPManual.Text.Trim()

    if (-not $m -or -not $mod) {
        [System.Windows.MessageBox]::Show("Selecione a marca e o modelo.", "Atencao", "OK", "Warning") | Out-Null
        return
    }

    if (-not $ip) {
        [System.Windows.MessageBox]::Show("Digite o endereco IP ou a porta da impressora.", "Atencao", "OK", "Warning") | Out-Null
        return
    }

    $state.Marca    = $m
    $state.Modelo   = $mod
    $state.Tipo     = if ($ip -like "USB*") { "USB" } else { "Rede" }
    $state.Endereco = $ip

    $lblResumoModelo.Text  = "Marca e Modelo: $m $mod"
    $lblResumoConexao.Text = "Conexao: $ip"

    $driverPronto = VerificarDriverPronto $m $mod
    if ($driverPronto) {
        $lblResumoDriver.Text = "Driver: Arquivos prontos no computador"
        $lblResumoDriver.Foreground = "#16A34A"
    } else {
        $lblResumoDriver.Text = "Driver: Sera baixado automaticamente da internet"
        $lblResumoDriver.Foreground = "#2563EB"
    }

    $txtNomePersonalizado.Text = "$m $mod ($ip)"
    MostrarPainel $painelConfiguracao
})

$btnFechar.Add_Click({ $window.Close() })

$btnNovaInstalacao.Add_Click({
    MostrarPainel $painelDescoberta
})

# ------------------------------------------------------------------------
# 7. INSTALACAO FINAL COM PERSONALIZACAO DO NOME E TESTE
# ------------------------------------------------------------------------
$btnInstalarConfirmado.Add_Click({
    $nomeFinal = $txtNomePersonalizado.Text.Trim()
    if (-not $nomeFinal) {
        [System.Windows.MessageBox]::Show("Por favor, informe um nome para a impressora.", "Atencao", "OK", "Warning") | Out-Null
        return
    }

    $m        = $state.Marca
    $mod      = $state.Modelo
    $endereco = $state.Endereco
    $tipo     = $state.Tipo

    $cfg = $Impressoras[$m][$mod]
    if (-not $cfg) {
        [System.Windows.MessageBox]::Show("Configuracoes nao encontradas para $m $mod.", "Erro", "OK", "Error") | Out-Null
        return
    }

    $tituloProgresso.Text = "Instalando: $nomeFinal"
    $btnFechar.Visibility = "Collapsed"
    $btnNovaInstalacao.Visibility = "Collapsed"
    MostrarPainel $painelProgresso
    AtualizarProgresso 5 "Iniciando instalacao..."

    try {
        $pastaModelo = ObterPastaModelo $m $mod
        
        # 1. Verifica se precisa baixar o driver
        $infFiles = @()
        if ($pastaModelo -and (Test-Path $pastaModelo)) {
            $infFiles = Get-ChildItem -Path $pastaModelo -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
        }

        $driverReadyInWindows = $false
        if ((-not $infFiles -or $infFiles.Count -eq 0) -and $chkDownload.IsChecked -and $cfg.DownloadUrl) {
            if (-not (Test-Path $pastaModelo)) { New-Item -ItemType Directory -Path $pastaModelo -Force | Out-Null }

            if ($m -eq "Epson") {
                AtualizarProgresso 15 "Baixando instalador oficial da Epson..."
                $tempPkg = Join-Path $pastaModelo "Epson_L6490_Installer.exe"
                $url = $cfg.DownloadUrl
                if (-not [Environment]::Is64BitOperatingSystem -and $cfg.DownloadUrlX86) {
                    $url = $cfg.DownloadUrlX86
                }
                try {
                    # Download fora da thread da janela, com Dispatcher ativo para evitar "Nao esta respondendo".
                    $downloadJob = Start-Job -ArgumentList $url, $tempPkg -ScriptBlock {
                        param($downloadUrl, $destino)
                        Invoke-WebRequest -Uri $downloadUrl -OutFile $destino -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
                    }
                    $downloadJobId = $downloadJob.Id
                    $downloadFrame = New-Object System.Windows.Threading.DispatcherFrame
                    $downloadTimer = New-Object System.Windows.Threading.DispatcherTimer
                    $downloadTimer.Interval = [TimeSpan]::FromMilliseconds(500)
                    $downloadStarted = [DateTime]::Now
                    $downloadTick = {
                        $jobAtual = Get-Job -Id $downloadJobId -ErrorAction SilentlyContinue
                        if (-not $jobAtual -or $jobAtual.State -in @('Completed','Failed','Stopped') -or ([DateTime]::Now - $downloadStarted).TotalMinutes -gt 11) {
                            if ($jobAtual -and $jobAtual.State -eq 'Running') { Stop-Job -Id $downloadJobId -ErrorAction SilentlyContinue }
                            $downloadTimer.Stop()
                            $downloadFrame.Continue = $false
                        } elseif (Test-Path -LiteralPath $tempPkg) {
                            $mb = [Math]::Round((Get-Item -LiteralPath $tempPkg).Length / 1MB, 1)
                            $txtEtapa.Text = "Baixando instalador Epson... $mb MB"
                        }
                    }.GetNewClosure()
                    $downloadTimer.Add_Tick($downloadTick)
                    $downloadTimer.Start()
                    [System.Windows.Threading.Dispatcher]::PushFrame($downloadFrame)
                    $jobFinal = Get-Job -Id $downloadJobId -ErrorAction SilentlyContinue
                    if (-not $jobFinal -or $jobFinal.State -ne 'Completed') {
                        $jobErro = if ($jobFinal -and $jobFinal.ChildJobs[0].JobStateInfo.Reason) { $jobFinal.ChildJobs[0].JobStateInfo.Reason.Message } else { "tempo limite excedido ou download interrompido" }
                        if ($jobFinal) { Remove-Job -Id $downloadJobId -Force -ErrorAction SilentlyContinue }
                        throw "Falha no download Epson: $jobErro"
                    }
                    Receive-Job -Id $downloadJobId -ErrorAction Stop | Out-Null
                    Remove-Job -Id $downloadJobId -Force -ErrorAction SilentlyContinue

                    AtualizarProgresso 25 "Extraindo os arquivos do driver Epson..."
                    & tar.exe -xf $tempPkg -C $pastaModelo 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "Nao foi possivel extrair o pacote Epson (codigo $LASTEXITCODE)." }
                    $infFiles = Get-ChildItem -Path $pastaModelo -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue

                    # Fallback: se um pacote futuro nao trouxer INF extraivel, abre o instalador oficial.
                    if (-not $infFiles -or $infFiles.Count -eq 0) {
                        AtualizarProgresso 25 "Pacote sem INF extraivel; abrindo o instalador oficial Epson..."
                        $process = Start-Process -FilePath $tempPkg -PassThru -ErrorAction Stop
                        $processFrame = New-Object System.Windows.Threading.DispatcherFrame
                        $processTimer = New-Object System.Windows.Threading.DispatcherTimer
                        $processTimer.Interval = [TimeSpan]::FromMilliseconds(500)
                        $processTick = {
                            try { $process.Refresh() } catch {}
                            if ($process.HasExited) {
                                $processTimer.Stop()
                                $processFrame.Continue = $false
                            }
                        }.GetNewClosure()
                        $processTimer.Add_Tick($processTick)
                        $processTimer.Start()
                        [System.Windows.Threading.Dispatcher]::PushFrame($processFrame)
                        $process.Refresh()
                        if ($process.ExitCode -ne 0) { throw "O instalador Epson encerrou com codigo $($process.ExitCode)." }
                        foreach ($driverName in $cfg.DriverNames) {
                            try {
                                if (Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue) {
                                    $driverReadyInWindows = $true
                                    break
                                }
                            } catch {}
                        }
                    }
                } catch {
                    throw "Nao foi possivel baixar ou executar o instalador oficial Epson. $($_.Exception.Message) Acesse: $($cfg.DownloadUrl)"
                }
                $infFiles = Get-ChildItem -Path $pastaModelo -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
            } else {
                AtualizarProgresso 15 "Baixando driver oficial do fabricante..."
                $url = $cfg.DownloadUrl
                if ($url -like "*.exe" -or $url -like "*.zip") {
                    $tempPkg = Join-Path $pastaModelo "pacote_driver.exe"
                    try {
                        Invoke-WebRequest -Uri $url -OutFile $tempPkg -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
                        AtualizarProgresso 25 "Extraindo arquivos do driver..."
                        & tar.exe -xf $tempPkg -C $pastaModelo 2>&1 | Out-Null
                    } catch {}
                }
                $infFiles = Get-ChildItem -Path $pastaModelo -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
            }
        }

        if ((-not $infFiles -or $infFiles.Count -eq 0) -and -not $driverReadyInWindows) {
            throw "Os arquivos do driver (.inf) nao foram encontrados em:`n$pastaModelo`n`nPara Epson L6490, o pacote oficial e um instalador: conclua a instalacao Epson ou baixe o driver pelo site oficial."
        }

        # 2. Publica o driver no repositorio do Windows (pnputil)
        AtualizarProgresso 35 "Publicando driver no Windows (pnputil)..."
        foreach ($inf in $infFiles) {
            $null = pnputil /add-driver "$($inf.FullName)" /install 2>&1
        }

        # 3. Configura a porta (TCP/IP ou USB)
        AtualizarProgresso 50 "Configurando porta da impressora..."
        $nomePorta = ""
        if ($tipo -eq "USB") {
            $nomePorta = $endereco
            if (-not $nomePorta) { $nomePorta = "USB001" }
        } else {
            $nomePorta = "IP_$endereco"
            $portaExiste = $false
            try {
                if (Get-PrinterPort -Name $nomePorta -ErrorAction SilentlyContinue) { $portaExiste = $true }
            } catch {}

            if (-not $portaExiste) {
                try {
                    Add-PrinterPort -Name $nomePorta -PrinterHostAddress $endereco -ErrorAction Stop
                } catch {
                    $portClass = [wmiclass]"Win32_TcpIpPrinterPort"
                    $newPort = $portClass.CreateInstance()
                    $newPort.Name = $nomePorta
                    $newPort.HostAddress = $endereco
                    $newPort.PortNumber = 9100
                    $newPort.Protocol = 1
                    $newPort.SNMPEnabled = $false
                    $newPort.Put() | Out-Null
                }
            }
        }

        # 4. Registra o driver no spooler
        AtualizarProgresso 65 "Registrando driver no spooler..."
        $driverParaAdicionar = $null
        foreach ($nome in $cfg.DriverNames) {
            try {
                if (Get-PrinterDriver -Name $nome -ErrorAction SilentlyContinue) {
                    $driverParaAdicionar = $nome
                    break
                }
            } catch {}
        }
        if (-not $driverParaAdicionar) {
            foreach ($nome in $cfg.DriverNames) {
                try {
                    Add-PrinterDriver -Name $nome -ErrorAction Stop
                    $driverParaAdicionar = $nome
                    break
                } catch {}
            }
        }
        if (-not $driverParaAdicionar) {
            $driverParaAdicionar = $cfg.DriverNames[0]
            Add-PrinterDriver -Name $driverParaAdicionar
        }

        # 5. Cria a impressora com o NOME PERSONALIZADO
        AtualizarProgresso 80 "Criando impressora '$nomeFinal'..."
        try {
            if (Get-Printer -Name $nomeFinal -ErrorAction SilentlyContinue) {
                Remove-Printer -Name $nomeFinal -ErrorAction SilentlyContinue
            }
        } catch {}

        Add-Printer -Name $nomeFinal -DriverName $driverParaAdicionar -PortName $nomePorta

        # 6. Pagina de teste
        if ($chkTeste.IsChecked) {
            AtualizarProgresso 92 "Enviando pagina de teste..."
            try {
                $wmiP = Get-CimInstance -ClassName Win32_Printer -Filter "Name='$($nomeFinal.Replace("'", "''"))'" -ErrorAction Stop
                if ($wmiP) { Invoke-CimMethod -InputObject $wmiP -MethodName PrintTestPage | Out-Null }
            } catch {
                try {
                    $wmiP = [wmi]"Win32_Printer.DeviceID='$($nomeFinal.Replace("'", "\'"))'"
                    if ($wmiP) { $wmiP.PrintTestPage() | Out-Null }
                } catch {}
            }
        }

        AtualizarProgresso 100 "Concluido com sucesso!"
        $tituloProgresso.Text = "Impressora Instalada com Sucesso!"
        $txtEtapa.Text = "A impressora '$nomeFinal' foi instalada e esta pronta para impressao na porta $nomePorta."
    }
    catch {
        $tituloProgresso.Text = "Falha na Instalacao"
        $txtPercentual.Text = "Erro"
        $txtEtapa.Text = "Detalhes do erro:`n" + $_.Exception.Message
    }
    finally {
        $btnFechar.Visibility = "Visible"
        $btnNovaInstalacao.Visibility = "Visible"
    }
})

# Inicia a busca automatica apos carregar a janela
$window.Add_Loaded({
    & $iniciarBusca
})

# Exibe a janela grafica
$window.ShowDialog() | Out-Null









