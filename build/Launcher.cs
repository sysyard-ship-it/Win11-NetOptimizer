using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

namespace Win11NetOptimizer
{
    class Program
    {
        [STAThread]
        static void Main()
        {
            try
            {
                // Extraer el script PowerShell incrustado como recurso
                string scriptPath = Path.Combine(Path.GetTempPath(), "Win11NetOptimizer_run.ps1");
                using (Stream res = Assembly.GetExecutingAssembly().GetManifestResourceStream("Win11-NetOptimizer.ps1"))
                {
                    if (res == null)
                    {
                        System.Windows.Forms.MessageBox.Show(
                            "No se encontro el recurso interno del script.",
                            "Win11 NetOptimizer", System.Windows.Forms.MessageBoxButtons.OK,
                            System.Windows.Forms.MessageBoxIcon.Error);
                        return;
                    }
                    using (FileStream fs = File.Create(scriptPath))
                        res.CopyTo(fs);
                }

                // Ejecutar con PowerShell sin consola visible (el exe ya es requireAdministrator)
                ProcessStartInfo psi = new ProcessStartInfo("powershell.exe",
                    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"");
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                Process p = Process.Start(psi);
                p.WaitForExit();

                // Limpiar archivo temporal
                try { File.Delete(scriptPath); } catch { }
            }
            catch (Exception ex)
            {
                System.Windows.Forms.MessageBox.Show(
                    "Error al iniciar: " + ex.Message,
                    "Win11 NetOptimizer", System.Windows.Forms.MessageBoxButtons.OK,
                    System.Windows.Forms.MessageBoxIcon.Error);
            }
        }
    }
}
