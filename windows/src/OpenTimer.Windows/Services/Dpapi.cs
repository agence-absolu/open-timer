using System.Runtime.InteropServices;
using System.Text;

namespace OpenTimer.Services;

/// <summary>
/// Chiffrement du token via DPAPI, lié au compte Windows courant.
///
/// Pendant du choix macOS mais dans l'autre sens : là-bas le trousseau a dû être abandonné
/// au profit d'un stockage en clair, parce que la signature ad-hoc change à chaque build et
/// invalidait l'entrée. DPAPI n'a pas ce défaut — il est lié à l'utilisateur, pas à la
/// signature du binaire — donc le token peut être chiffré au repos ici.
///
/// Appel direct de crypt32.dll plutôt que du paquet System.Security.Cryptography.ProtectedData,
/// qui est une dépendance NuGet : le projet tient au zéro dépendance externe.
/// </summary>
internal static class Dpapi
{
    public static string Protect(string plain)
    {
        if (plain.Length == 0) return "";
        var bytes = Encoding.UTF8.GetBytes(plain);
        return Convert.ToBase64String(Transform(bytes, encrypt: true));
    }

    public static string Unprotect(string protectedBase64)
    {
        if (protectedBase64.Length == 0) return "";
        try
        {
            var bytes = Convert.FromBase64String(protectedBase64);
            return Encoding.UTF8.GetString(Transform(bytes, encrypt: false));
        }
        catch
        {
            // Profil Windows différent, données corrompues : on repart d'un token vide
            // plutôt que d'empêcher l'app de démarrer.
            return "";
        }
    }

    private static byte[] Transform(byte[] input, bool encrypt)
    {
        var inBlob = new DataBlob();
        var outBlob = new DataBlob();
        try
        {
            inBlob.cbData = input.Length;
            inBlob.pbData = Marshal.AllocHGlobal(input.Length);
            Marshal.Copy(input, 0, inBlob.pbData, input.Length);

            var ok = encrypt
                ? CryptProtectData(ref inBlob, "OpenTimer", IntPtr.Zero, IntPtr.Zero, IntPtr.Zero,
                    CryptprotectUiForbidden, ref outBlob)
                : CryptUnprotectData(ref inBlob, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero,
                    CryptprotectUiForbidden, ref outBlob);

            if (!ok) throw new InvalidOperationException("Échec DPAPI.");

            var output = new byte[outBlob.cbData];
            Marshal.Copy(outBlob.pbData, output, 0, outBlob.cbData);
            return output;
        }
        finally
        {
            if (inBlob.pbData != IntPtr.Zero) Marshal.FreeHGlobal(inBlob.pbData);
            if (outBlob.pbData != IntPtr.Zero) Marshal.FreeHGlobal(outBlob.pbData);
        }
    }

    private const int CryptprotectUiForbidden = 0x1;

    [StructLayout(LayoutKind.Sequential)]
    private struct DataBlob
    {
        public int cbData;
        public IntPtr pbData;
    }

    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptProtectData(
        ref DataBlob pDataIn, string szDataDescr, IntPtr pOptionalEntropy, IntPtr pvReserved,
        IntPtr pPromptStruct, int dwFlags, ref DataBlob pDataOut);

    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptUnprotectData(
        ref DataBlob pDataIn, IntPtr ppszDataDescr, IntPtr pOptionalEntropy, IntPtr pvReserved,
        IntPtr pPromptStruct, int dwFlags, ref DataBlob pDataOut);
}
