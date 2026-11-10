using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace PrinterInstaller
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            try
            {
                string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                string scriptPath = Path.Combine(exeDir, "InstaladorImpressoras.ps1");
                
                if (!File.Exists(scriptPath))
                {
                    MessageBox.Show(
                        "O arquivo de script 'InstaladorImpressoras.ps1' não foi encontrado na pasta:\n\n" + exeDir + 
                        "\n\nCertifique-se de manter o executável na mesma pasta do script.",
                        "Arquivo não encontrado - TI Prefeitura",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return;
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = string.Format("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{0}\"", scriptPath);
                psi.WorkingDirectory = exeDir;
                psi.UseShellExecute = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;

                Process p = Process.Start(psi);
                if (p != null)
                {
                    // Aguarda o término ou deixa rodar independente
                }
            }
            catch (System.ComponentModel.Win32Exception ex)
            {
                // Código 1223 = Usuário cancelou a tela UAC do Windows
                if (ex.NativeErrorCode != 1223)
                {
                    MessageBox.Show(
                        "Não foi possível iniciar o instalador com privilégios de Administrador:\n\n" + ex.Message,
                        "Erro de Inicialização",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Ocorreu um erro ao abrir o instalador:\n\n" + ex.Message,
                    "Erro Inesperado",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }
    }
}
