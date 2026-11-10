using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

public class DiscoveredPrinter {
    public string IP { get; set; }
    public string Name { get; set; }
    public string Model { get; set; }
    public string Brand { get; set; }
    public string Type { get; set; }      // "Rede" ou "USB"
    public string PortName { get; set; }
    public bool DriverReady { get; set; }

    public string DisplayTitle {
        get {
            string tag = Type == "USB" ? "[USB]" : "[REDE]";
            return string.Format("{0} {1}", tag, Name);
        }
    }

    public string DisplaySubtitle {
        get {
            if (Type == "USB") {
                return string.Format("Conexão: Cabo USB • Modelo sugerido: {0}", Model);
            } else {
                return string.Format("IP: {0} • Modelo sugerido: {1}", IP, Model);
            }
        }
    }
}

public class FastPrinterDiscovery {
    public static Task<List<DiscoveredPrinter>> ScanAllAsync(List<string> subnets, int timeoutMs) {
        return Task.Factory.StartNew(() => ScanAll(subnets, timeoutMs));
    }

    public static List<DiscoveredPrinter> ScanAll(List<string> subnets, int timeoutMs) {
        List<DiscoveredPrinter> result = new List<DiscoveredPrinter>();

        // 1. Escaneia dispositivos USB
        // 1. Escaneia dispositivos USB conectados
        try {
            List<DiscoveredPrinter> usbPrinters = ScanUsb();
            foreach (var p in usbPrinters) {
                result.Add(p);
            }
        } catch {}

        // 2. Escaneia subredes na rede local
        if (subnets != null) {
            foreach (string subnet in subnets) {
                if (!string.IsNullOrEmpty(subnet)) {
                    try {
                        List<DiscoveredPrinter> netPrinters = ScanNetwork(subnet, timeoutMs);
                        foreach (var p in netPrinters) {
                            result.Add(p);
                        }
                    } catch {}
                }
            }
        }

        return result;
    }

    public static List<DiscoveredPrinter> ScanNetwork(string subnetBase, int timeoutMs) {
        List<DiscoveredPrinter> list = new List<DiscoveredPrinter>();
        List<string> ips = new List<string>();

        if (subnetBase.EndsWith(".")) {
            for (int i = 1; i <= 254; i++) ips.Add(subnetBase + i);
        } else if (subnetBase.Contains("/")) {
            string[] cidr = subnetBase.Split('/');
            IPAddress address;
            int prefix;
            if (cidr.Length != 2 || !IPAddress.TryParse(cidr[0], out address) ||
                address.AddressFamily != AddressFamily.InterNetwork || !int.TryParse(cidr[1], out prefix) || prefix < 1 || prefix > 32) {
                return list;
            }
            byte[] bytes = address.GetAddressBytes();
            uint value = ((uint)bytes[0] << 24) | ((uint)bytes[1] << 16) | ((uint)bytes[2] << 8) | bytes[3];
            uint mask = prefix == 0 ? 0u : 0xFFFFFFFFu << (32 - prefix);
            uint network = value & mask;
            uint broadcast = network | ~mask;
            ulong first = prefix >= 31 ? network : (ulong)network + 1;
            ulong last = prefix >= 31 ? broadcast : (ulong)broadcast - 1;
            for (ulong current = first; current <= last; current++) {
                uint ipValue = (uint)current;
                ips.Add(string.Format("{0}.{1}.{2}.{3}", (ipValue >> 24) & 255, (ipValue >> 16) & 255, (ipValue >> 8) & 255, ipValue & 255));
            }
        } else {
            ips.Add(subnetBase);
        }

        Parallel.ForEach(ips, new ParallelOptions { MaxDegreeOfParallelism = 60 }, ip => {
            // Portas padrao de impressao: RAW/JetDirect, LPD e IPP.
            bool port9100 = CheckPort(ip, 9100, timeoutMs);
            bool port515 = CheckPort(ip, 515, timeoutMs);
            bool port631 = CheckPort(ip, 631, timeoutMs);
            bool port80 = CheckPort(ip, 80, timeoutMs);
            bool port443 = CheckPort(ip, 443, timeoutMs);

            string title = (port80 || port443 || port631) ? GetHttpTitle(ip, 1200) : null;
            string hostName = (port9100 || port515 || port631 || port80 || port443) ? GetHostName(ip) : null;
            string identity = ((title ?? "") + " " + (hostName ?? "")).ToLowerInvariant();
            bool nomeIndicaImpressora = identity.Contains("printer") || identity.Contains("impress") ||
                identity.Contains("epson") || identity.Contains("brother") || identity.Contains("canon") ||
                identity.Contains("ecotank") || identity.Contains("pixma") || identity.Contains("imageclass");

            // Evita listar qualquer computador que tenha apenas uma pagina web comum.
            if (port9100 || port515 || port631 || ((port80 || port443) && nomeIndicaImpressora)) {
                DiscoveredPrinter dp = new DiscoveredPrinter();
                dp.IP = ip;
                dp.Type = "Rede";
                dp.PortName = "IP_" + ip;
                string bestName = !string.IsNullOrEmpty(title) ? title : (!string.IsNullOrEmpty(hostName) ? hostName : ("Impressora de rede (" + ip + ")"));
                dp.Name = CleanPrinterName(bestName);
                ClassifyDevice(dp);
                lock (list) { list.Add(dp); }
            }
        });
        return list;
    }

    public static List<DiscoveredPrinter> ScanUsb() {
        List<DiscoveredPrinter> list = new List<DiscoveredPrinter>();
        try {
            using (Microsoft.Win32.RegistryKey key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Enum\USBPRINT")) {
                if (key != null) {
                    foreach (string subkeyName in key.GetSubKeyNames()) {
                        using (Microsoft.Win32.RegistryKey sub = key.OpenSubKey(subkeyName)) {
                            if (sub != null) {
                                foreach (string instName in sub.GetSubKeyNames()) {
                                    using (Microsoft.Win32.RegistryKey inst = sub.OpenSubKey(instName)) {
                                        if (inst != null) {
                                            string name = inst.GetValue("FriendlyName") as string;
                                            if (string.IsNullOrEmpty(name)) {
                                                name = inst.GetValue("DeviceDesc") as string;
                                            }
                                            if (!string.IsNullOrEmpty(name)) {
                                                DiscoveredPrinter dp = new DiscoveredPrinter();
                                                dp.Name = CleanPrinterName(name);
                                                dp.Type = "USB";
                                                dp.PortName = "USB001";
                                                dp.IP = "USB";
                                                ClassifyDevice(dp);
                                                list.Add(dp);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {}
        return list;
    }

    private static bool CheckPort(string ip, int port, int timeout) {
        try {
            using (TcpClient client = new TcpClient()) {
                IAsyncResult ar = client.BeginConnect(ip, port, null, null);
                if (ar.AsyncWaitHandle.WaitOne(timeout, false)) {
                    client.EndConnect(ar);
                    return true;
                }
            }
        } catch {}
        return false;
    }

    private static string GetHttpTitle(string ip, int timeout) {
        try {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create("http://" + ip);
            req.Timeout = timeout;
            req.ReadWriteTimeout = timeout;
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse()) {
                using (System.IO.StreamReader r = new System.IO.StreamReader(resp.GetResponseStream())) {
                    char[] buf = new char[4096];
                    int len = r.Read(buf, 0, buf.Length);
                    string s = new string(buf, 0, len);
                    int start = s.IndexOf("<title>", StringComparison.OrdinalIgnoreCase);
                    if (start >= 0) {
                        start += 7;
                        int end = s.IndexOf("</title>", start, StringComparison.OrdinalIgnoreCase);
                        if (end > start) return s.Substring(start, end - start).Trim();
                    }
                }
            }
        } catch {}
        return null;
    }

    private static string GetHostName(string ip) {
        try {
            IPHostEntry e = Dns.GetHostEntry(ip);
            return e.HostName;
        } catch {}
        return null;
    }

    private static string CleanPrinterName(string raw) {
        if (string.IsNullOrEmpty(raw)) return "Impressora";
        string s = raw.Replace("\r", "").Replace("\n", "").Trim();
        if (s.Length > 40) s = s.Substring(0, 40);
        return s;
    }

    private static void ClassifyDevice(DiscoveredPrinter dp) {
        string search = (dp.Name + " " + dp.IP).ToLowerInvariant();
        if (search.Contains("gx70") || search.Contains("g7000") || search.Contains("g7010") || search.Contains("gx7000") || search.Contains("gx7010")) {
            dp.Brand = "Canon";
            dp.Model = "GX7010 / GX7000";
        } else if (search.Contains("1643") || search.Contains("imagerunner") || search.Contains("generic plus")) {
            dp.Brand = "Canon";
            dp.Model = "imageRUNNER 1643iF";
        } else if (search.Contains("5652") || search.Contains("dcp-l5652")) {
            dp.Brand = "Brother";
            dp.Model = "DCP-L5652DN";
        } else if (search.Contains("6490") || search.Contains("l6490")) {
            dp.Brand = "Epson";
            dp.Model = "EcoTank L6490";
        } else if (search.Contains("brother") || search.Contains("brw")) {
            dp.Brand = "Brother";
            dp.Model = "Modelo nao identificado";
        } else if (search.Contains("epson") || search.Contains("ecotank") || search.Contains("workforce")) {
            dp.Brand = "Epson";
            dp.Model = "Modelo nao identificado";
        } else if (search.Contains("canon")) {
            dp.Brand = "Canon";
            dp.Model = "Modelo nao identificado";
        } else {
            // Nao atribui Canon por padrao: a marca/modelo podem ser definidos manualmente.
            dp.Brand = "Outra";
            dp.Model = "Impressora de rede";
        }
    }
}



