<#
==============================================================================
 AUXILIAR DE DRIVERS - TI PREFEITURA
==============================================================================
 Este script verifica o status de cada driver na pasta local 'Drivers'
 e fornece atalhos diretos para download e orientações de extração.
==============================================================================
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = "C:\Impressora IT (Útil)" }
$DriversDir = Join-Path $ScriptDir "Drivers"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       STATUS DOS DRIVERS DE IMPRESSORA - TI PREFEITURA         " -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Pasta base: $DriversDir`n" -ForegroundColor Gray

$modelos = @(
    @{
        Marca    = "Canon"
        Modelo   = "imageCLASS X MF1643i II / imageRUNNER 1643i II"
        Pasta    = "Canon\iR1643iII"
        Site     = "https://in.canon/en/support/0101118801"
        Pacote   = "Generic Plus UFR II Printer Driver (x64)"
    },
    @{
        Marca    = "Canon"
        Modelo   = "imageCLASS X MF1643iF II / imageRUNNER 1643iF II"
        Pasta    = "Canon\iR1643iFII"
        Site     = "https://in.canon/en/support/0101118801"
        Pacote   = "Generic Plus UFR II Printer Driver (x64)"
    },
    @{
        Marca    = "Canon"
        Modelo   = "imageRUNNER 1643iF"
        Pasta    = "Canon\iR1643iF"
        Site     = "https://www.usa.canon.com/support/p/imagerunner-1643if"
        Pacote   = "Generic Plus PCL6 Printer Driver (x64)"
    },
    @{
        Marca    = "Canon"
        Modelo   = "GX7010 / GX7000"
        Pasta    = "Canon\GX7000"
        Site     = "https://www.canon.com.br/support"
        Pacote   = "Driver de impressora G7000 / GX7000 series (x64)"
    },
    @{
        Marca    = "Brother"
        Modelo   = "DCP-L5652DN"
        Pasta    = "Brother\DCPL5652DN"
        Site     = "https://support.brother.com/g/b/downloadlist.aspx?c=br&lang=pt&prod=dcpl5652dn_us_eu_as&os=10013"
        Pacote   = "Pacote Completo de Drivers e Software (ou Driver de Impressora)"
    },
    @{
        Marca    = "Epson"
        Modelo   = "EcoTank L6490"
        Pasta    = "Epson\L6490"
        Site     = "https://epson.com.br/Suporte/Impressoras/Impressoras-multifuncionais/Epson-L/Epson-L6490/s/SPT_C11CJ88301"
        Pacote   = "Instalador do Pacote de Drivers e Utilitários"
    }
)

foreach ($m in $modelos) {
    $caminho = Join-Path $DriversDir $m.Pasta
    $existe = Test-Path $caminho
    $infFiles = @()
    if ($existe) {
        $infFiles = Get-ChildItem -Path $caminho -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    }

    Write-Host "[$($m.Marca)] $($m.Modelo)" -ForegroundColor White
    Write-Host "  Pasta: $($m.Pasta)" -ForegroundColor Gray
    
    if ($infFiles.Count -gt 0) {
        Write-Host "  Status: [PRONTO] Encontrados $($infFiles.Count) arquivo(s) .inf" -ForegroundColor Green
    } elseif ($existe) {
        Write-Host "  Status: [PENDENTE] Pasta existe, mas falta extrair os arquivos do driver (.inf)" -ForegroundColor Yellow
        Write-Host "  Download: $($m.Site)" -ForegroundColor DarkCyan
    } else {
        Write-Host "  Status: [FALTANDO] Pasta não encontrada" -ForegroundColor Red
        Write-Host "  Download: $($m.Site)" -ForegroundColor DarkCyan
    }
    Write-Host ""
}

Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
Write-Host "OPÇÕES:" -ForegroundColor Yellow
Write-Host "1 - Abrir o site de download da Brother DCP-L5652DN"
Write-Host "2 - Abrir o site de download da Epson L6490"
Write-Host "3 - Abrir a pasta de Drivers no Windows Explorer"
Write-Host "4 - Sair"
Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray

$opcao = Read-Host "Digite a opção desejada (1-4)"

switch ($opcao) {
    "1" {
        Start-Process "https://support.brother.com/g/b/downloadlist.aspx?c=br&lang=pt&prod=dcpl5652dn_us_eu_as&os=10013"
    }
    "2" {
        Start-Process "https://epson.com.br/Suporte/Impressoras/Impressoras-multifuncionais/Epson-L/Epson-L6490/s/SPT_C11CJ88301"
    }
    "3" {
        Start-Process explorer.exe $DriversDir
    }
    Default {
        Write-Host "Encerrando."
    }
}

