using System.Globalization;

namespace OpenTimer.Models;

/// <summary>
/// Une saisie de temps déjà enregistrée dans OpenProject.
/// </summary>
/// <param name="SpentOn">Date au format « yyyy-MM-dd ».</param>
/// <param name="Seconds">Durée en secondes, parsée depuis le champ ISO 8601 <c>hours</c>.</param>
/// <param name="StartTime">Instant de début en UTC (si l'option est activée sur l'instance).</param>
/// <param name="EndTime">Instant de fin en UTC (idem).</param>
/// <param name="CreatedAt">Création de la saisie en UTC = arrêt du chrono pour les saisies faites par l'app.</param>
/// <param name="LockVersion">Verrou optimiste requis par OpenProject pour le PATCH.</param>
public sealed record TimeEntry(
    int Id,
    string? WorkPackageTitle,
    string? WorkPackageHref,
    string? ProjectTitle,
    string Comment,
    string SpentOn,
    int Seconds,
    DateTime? StartTime,
    DateTime? EndTime,
    DateTime? CreatedAt,
    int? LockVersion)
{
    /// <summary>ID numérique du work package, extrait du href HAL (<c>/api/v3/work_packages/{id}</c>).</summary>
    public int? WorkPackageId
    {
        get
        {
            var last = WorkPackageHref?.Split('/').LastOrDefault();
            return int.TryParse(last, out var id) ? id : null;
        }
    }

    /// <summary>Date reformatée jj/MM/aaaa pour l'affichage.</summary>
    public string DisplayDate =>
        DateTime.TryParseExact(SpentOn, "yyyy-MM-dd", CultureInfo.InvariantCulture,
            DateTimeStyles.None, out var d)
            ? d.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture)
            : SpentOn;
}
