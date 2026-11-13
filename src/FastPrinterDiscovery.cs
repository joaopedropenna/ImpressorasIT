using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
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
    private static int _progressPercent = 0;

    public static int GetProgressPercent() {
        return Interlocked.CompareExchange(ref _progressPercent, 0, 0);
    }

    private static void SetProgressPercent(int value) {
        Interlocked.Exchange(ref _progressPercent, Math.Max(0, Math.Min(100, value)));
    }
    public static Task<List<DiscoveredPrinter>> ScanAllAsync(List<string> subnets, int timeoutMs) {
        return Task.Factory.StartNew(() => ScanAll(subnets, timeoutMs));
    }

    public static List<DiscoveredPrinter> ScanAll(List<string> subnets, int timeoutMs) {
        SetProgressPercent(0);
        List<DiscoveredPrinter> result = new List<DiscoveredPrinter>();

        // 1. Escaneia dispositivos USB
        // 1. Escaneia dispositivos USB conectados
        try {
            List<DiscoveredPrinter> usbPrinters = ScanUsb();
            foreach (var p in usbPrinters) {
                result.Add(p);
            }
        } catch {}
        SetProgressPercent(5);

        // 2. Escaneia subredes na rede local
        List<string> networks = new List<string>();
        if (subnets != null) {
            foreach (string subnet in subnets) if (!string.IsNullOrEmpty(subnet)) networks.Add(subnet);
        }
        if (networks.Count == 0) {
            SetProgressPercent(100);
        } else {
            SetProgressPercent(10);
            for (int i = 0; i < networks.Count; i++) {
                int progressStart = 10 + (90 * i / networks.Count);
                int progressEnd = 10 + (90 * (i + 1) / networks.Count);
                try {
                    List<DiscoveredPrinter> netPrinters = ScanNetworkInternal(networks[i], timeoutMs, progressStart, progressEnd - progressStart);
                    foreach (var p in netPrinters) result.Add(p);
                } catch {}
            }
        }
        SetProgressPercent(100);
        return result;
    }

    public static List<DiscoveredPrinter> ScanNetwork(string subnetBase, int timeoutMs) {
        return ScanNetworkInternal(subnetBase, timeoutMs, 10, 90);
    }

    private static List<DiscoveredPrinter> ScanNetworkInternal(string subnetBase, int timeoutMs, int progressStart, int progressSpan) {
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

        if (ips.Count == 0) { SetProgressPercent(progressStart + progressSpan); return list; }
        int completedHosts = 0;
        Parallel.ForEach(ips, new ParallelOptions { MaxDegreeOfParallelism = 64 }, ip => {
            try {
            // Examina os IPs em paralelo e limita o tempo de cada porta testada.
            bool[] ports = CheckPorts(ip, new int[] { 9100, 515, 631, 80 }, Math.Max(timeoutMs, 300));
            bool port9100 = ports[0];
            bool port515 = ports[1];
            bool port631 = ports[2];
            bool port80 = ports[3];

            string title = port80 ? GetHttpTitle(ip, 80, 700) : (port631 ? GetHttpTitle(ip, 631, 700) : null);
            string snmpInfo = null;
            if (!(port9100 || port515 || port631)) snmpInfo = GetSnmpPrinterDescription(ip, Math.Max(timeoutMs, 300));
            string identity = ((title ?? "") + " " + (snmpInfo ?? "")).ToLowerInvariant();
            bool nomeIndicaImpressora = identity.Contains("printer") || identity.Contains("impress") ||
                identity.Contains("epson") || identity.Contains("brother") || identity.Contains("canon") ||
                identity.Contains("ecotank") || identity.Contains("pixma") || identity.Contains("imageclass") ||
                identity.Contains("laserjet") || identity.Contains("workforce") || identity.Contains("ricoh") ||
                identity.Contains("kyocera") || identity.Contains("xerox") || identity.Contains("lexmark") ||
                identity.Contains("sharp") || identity.Contains("konica") || identity.Contains("mfp");

            // Filtra páginas web comuns; SNMP permite reconhecer impressoras sem RAW/LPD/IPP.
            bool temPortaImpressao = port9100 || port515 || port631;
            bool impressoraWebOuSnmp = (port80 && nomeIndicaImpressora) || !string.IsNullOrEmpty(snmpInfo);
            if (temPortaImpressao || impressoraWebOuSnmp) {
                DiscoveredPrinter dp = new DiscoveredPrinter();
                dp.IP = ip;
                dp.Type = "Rede";
                dp.PortName = "IP_" + ip;
                string bestName = !string.IsNullOrEmpty(title) ? title : (!string.IsNullOrEmpty(snmpInfo) ? snmpInfo : ("Impressora de rede (" + ip + ")"));
                dp.Name = CleanPrinterName(bestName);
                ClassifyDevice(dp);
                lock (list) { list.Add(dp); }
            }
            } finally {
                int completed = Interlocked.Increment(ref completedHosts);
                int percent = progressStart + (int)((long)progressSpan * completed / ips.Count);
                SetProgressPercent(percent);
            }
        });
        SetProgressPercent(progressStart + progressSpan);
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

    private static bool[] CheckPorts(string ip, int[] ports, int timeout) {
        bool[] result = new bool[ports.Length];
        for (int i = 0; i < ports.Length; i++) result[i] = CheckPort(ip, ports[i], timeout);
        return result;
    }

    private static bool CheckPort(string ip, int port, int timeout) {
        try {
            using (TcpClient client = new TcpClient()) {
                IAsyncResult attempt = client.BeginConnect(ip, port, null, null);
                bool connected;
                WaitHandle waitHandle = attempt.AsyncWaitHandle;
                using (waitHandle) { connected = waitHandle.WaitOne(timeout, false); }
                if (!connected) { try { client.Close(); } catch {} return false; }
                client.EndConnect(attempt);
                return true;
            }
        } catch {}
        return false;
    }

    private static string GetSnmpPrinterDescription(string ip, int timeout) {
        // SNMP v1 GET system.sysDescr.0 com community publica (OID 1.3.6.1.2.1.1.1.0).
        byte[] request = new byte[] {
            0x30,0x26,0x02,0x01,0x00,0x04,0x06,0x70,0x75,0x62,0x6c,0x69,0x63,
            0xa0,0x19,0x02,0x01,0x01,0x02,0x01,0x00,0x02,0x01,0x00,0x30,0x0e,
            0x30,0x0c,0x06,0x08,0x2b,0x06,0x01,0x02,0x01,0x01,0x01,0x00,0x05,0x00
        };
        try {
            using (UdpClient client = new UdpClient()) {
                client.Client.ReceiveTimeout = timeout;
                client.Client.SendTimeout = timeout;
                IPEndPoint target = new IPEndPoint(IPAddress.Parse(ip), 161);
                client.Send(request, request.Length, target);
                IPEndPoint source = new IPEndPoint(IPAddress.Any, 0);
                byte[] response = client.Receive(ref source);
                string raw = Encoding.ASCII.GetString(response);
                StringBuilder printable = new StringBuilder();
                foreach (char ch in raw) printable.Append(ch >= 32 && ch <= 126 ? ch : ' ');
                string description = printable.ToString().Trim();
                string lower = description.ToLowerInvariant();
                string[] markers = new string[] { "printer", "print", "canon", "epson", "brother", "hewlett", "hp ", "laserjet", "imageclass", "workforce", "ricoh", "kyocera", "xerox", "lexmark", "sharp", "konica", "mfp" };
                foreach (string marker in markers) {
                    int markerIndex = lower.IndexOf(marker, StringComparison.Ordinal);
                    if (markerIndex >= 0) return description.Substring(markerIndex).Trim();
                }
            }
        } catch {}
        return null;
    }

    private static string GetHttpTitle(string ip, int port, int timeout) {
        try {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create("http://" + ip + ":" + port + "/");
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
        } else if (search.Contains("1643if ii") || search.Contains("1643iif ii")) {
            dp.Brand = "Canon";
            dp.Model = "imageCLASS X MF1643iF II / imageRUNNER 1643iF II";
        } else if (search.Contains("1643i ii") || search.Contains("1643ii")) {
            dp.Brand = "Canon";
            dp.Model = "imageCLASS X MF1643i II / imageRUNNER 1643i II";
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

