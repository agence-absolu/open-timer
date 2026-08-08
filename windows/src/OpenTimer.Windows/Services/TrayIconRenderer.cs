using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace OpenTimer.Services;

/// <summary>
/// Fabrique l'icône de la zone de notification.
///
/// Contrairement à macOS, la barre des tâches Windows n'affiche <b>que</b> une icône —
/// pas de texte à côté. Le chrono qui défile dans la barre de menu n'a donc pas
/// d'équivalent direct : on dessine la durée <b>dans</b> l'icône, au format H:MM
/// (les secondes sont illisibles à cette taille), sur un fond rouge d'enregistrement.
///
/// Les HICON produits sont des ressources GDI non gérées : l'appelant doit disposer
/// l'icône précédente avant de la remplacer, sinon la fuite est d'un handle par minute.
/// <see cref="TrayService"/> s'en charge.
/// </summary>
public static class TrayIconRenderer
{
    private static readonly Color Recording = Color.FromArgb(0xE5, 0x3E, 0x3E);

    /// <summary>
    /// Icône affichant <paramref name="elapsed"/> au format H:MM. Au-delà de 10 heures,
    /// bascule sur le nombre d'heures seul — quatre chiffres plus un « : » ne tiennent pas.
    /// </summary>
    public static Icon RenderElapsed(TimeSpan elapsed, bool paused)
    {
        var totalMinutes = (int)Math.Max(0, elapsed.TotalMinutes);
        var hours = totalMinutes / 60;
        var text = hours >= 10 ? $"{hours}h" : $"{hours}:{totalMinutes % 60:00}";
        return Render(text, paused ? Color.FromArgb(0x8A, 0x8A, 0x8E) : Recording);
    }

    /// <summary>Dessine un texte court centré sur une pastille pleine, à la taille d'icône système.</summary>
    private static Icon Render(string text, Color background)
    {
        // La taille dépend du DPI (16 px en 100 %, davantage au-delà) : la lire évite une
        // icône floue sur les écrans haute densité.
        var size = Math.Max(16, SystemInformation.SmallIconSize.Width);

        using var bitmap = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            g.Clear(Color.Transparent);

            using var brush = new SolidBrush(background);
            g.FillEllipse(brush, 0, 0, size - 1, size - 1);

            // Police ajustée à la largeur : 4 caractères doivent tenir dans le diamètre.
            var fontSize = size * 0.40f;
            using var font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel);
            using var format = new StringFormat
            {
                Alignment = StringAlignment.Center,
                LineAlignment = StringAlignment.Center,
            };
            g.DrawString(text, font, Brushes.White, new RectangleF(0, 0, size, size), format);
        }

        return FromBitmap(bitmap);
    }

    /// <summary>
    /// Icône au repos : la ressource embarquée du projet. Chargée à chaque appel pour rester
    /// symétrique avec <see cref="RenderElapsed"/>, dont l'appelant dispose le résultat.
    /// </summary>
    public static Icon RenderIdle()
    {
        var stream = System.Windows.Application.GetResourceStream(
            new Uri("pack://application:,,,/Resources/app.ico"))?.Stream;
        if (stream is not null)
        {
            using (stream) return new Icon(stream, SystemInformation.SmallIconSize);
        }
        return Render("", Color.FromArgb(0x6E, 0x6E, 0x73));
    }

    /// <summary>
    /// Convertit le bitmap en <see cref="Icon"/> autonome : <c>Icon.FromHandle</c> ne copie
    /// pas le handle, on clone donc avant de détruire le HICON temporaire.
    /// </summary>
    private static Icon FromBitmap(Bitmap bitmap)
    {
        var handle = bitmap.GetHicon();
        try
        {
            using var temp = Icon.FromHandle(handle);
            return (Icon)temp.Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);
}
