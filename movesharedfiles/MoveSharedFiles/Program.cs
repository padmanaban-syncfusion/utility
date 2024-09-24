using System;
using System.IO;
using System.Xml;
using Newtonsoft.Json;

namespace ExtractAppData
{
    class Program
    {
        static void Main(string[] args)
        {
            try
            {
                var sourcePath = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory + "/app_data");
                var destPath = string.Empty;
                if (args.Length != 0)
                {
                    destPath = Path.GetFullPath(args[0]);
                }
                else
                {
                    destPath = "/application/app_data";
                }

                //// Read and write Config.xml
                if (!File.Exists(destPath + "/configuration/config.xml"))
                {
                    CloneDirectory(sourcePath + "/configuration", destPath + "/configuration");
                }

                if (Directory.Exists(destPath + "/optional-libs"))
                {
                    Console.WriteLine($"Deleting {destPath}/optional-libs");
                    Directory.Delete(destPath + "/optional-libs", true);
                }

                if (!File.Exists(destPath + "/optional-libs/optional-libs.txt"))
                {
                    CloneDirectory(sourcePath + "/optional-libs", destPath + "/optional-libs");
                }

                //Write Base URL to config file
                var baseUrl = Environment.GetEnvironmentVariable("APP_BASE_URL");
                var isInvalidConfigBaseUrl = false;

                if (File.Exists(destPath + "/configuration/config.xml"))
                {
                    XmlDocument doc = new XmlDocument();
                    XmlTextReader reader = new XmlTextReader(destPath + "/configuration/config.xml");
                    reader.Read();
                    doc.Load(reader);
                    foreach (XmlNode a in doc.GetElementsByTagName("SystemSettings"))
                    {
                        foreach (XmlNode b in a.SelectNodes("InternalAppUrls"))
                        {
                            isInvalidConfigBaseUrl = b.SelectNodes("Idp").Item(0).InnerText.StartsWith("http://localhost") ||
                            b.SelectNodes("Reports").Item(0).InnerText.StartsWith("http://localhost") ||
                            b.SelectNodes("ReportsService").Item(0).InnerText.StartsWith("http://localhost");
                        }
                    }
                }

                if (!File.Exists(destPath + "/configuration/product.json"))
                {
                    string json = File.ReadAllText(sourcePath + "/configuration/product.json");
                    dynamic jsonObj = Newtonsoft.Json.JsonConvert.DeserializeObject(json);

                    if (!string.IsNullOrWhiteSpace(baseUrl)
                        && !(baseUrl.Contains('<') && baseUrl.Contains('>'))
                        && (!File.Exists(destPath + "/configuration/config.xml") || isInvalidConfigBaseUrl))
                    {
                        Console.WriteLine("BaseUrl: " + baseUrl);
                        jsonObj["InternalAppUrl"]["Idp"] = baseUrl;
                        jsonObj["InternalAppUrl"]["Reports"] = baseUrl + "/reporting";
                        jsonObj["InternalAppUrl"]["ReportsService"] = baseUrl + "/reporting/reportservice";
                    }

                    string output = Newtonsoft.Json.JsonConvert.SerializeObject(jsonObj, Newtonsoft.Json.Formatting.Indented);
                    CloneDirectory(sourcePath + "/configuration", destPath + "/configuration");
                    File.WriteAllText(destPath + "/configuration/product.json", output);
                }

                //Write user input on optional libraries in text file
                var optionalLibs = Environment.GetEnvironmentVariable("INSTALL_OPTIONAL_LIBS");
                if (!string.IsNullOrWhiteSpace(optionalLibs) && !(optionalLibs.Contains('<') && optionalLibs.Contains('>')))
                {
                    File.WriteAllText(destPath + "/optional-libs/optional-libs.txt", optionalLibs);
                }                
            }
            catch (Exception ex)
            {
                Console.WriteLine("Exception: " + ex.Message);
            }
        }

        private static void CloneDirectory(string source, string dest)
        {
            if (!Directory.Exists(dest))
            {
                Directory.CreateDirectory(dest);
            }

            foreach (var directory in Directory.GetDirectories(source))
            {
                string dirName = Path.GetFileName(directory);                
                CloneDirectory(directory, Path.Combine(dest, dirName));
            }

            foreach (var file in Directory.GetFiles(source))
            {
                File.Copy(file, Path.Combine(dest, Path.GetFileName(file)));
            }
        }
    }
}
