namespace OpenTimer.Models;

/// <summary>
/// Un work package OpenProject, décodé depuis la représentation HAL de l'API v3.
/// </summary>
public sealed record WorkPackage(int Id, string Subject, string? ProjectName)
{
    public string Href => $"/api/v3/work_packages/{Id}";

    public string Display => string.IsNullOrEmpty(ProjectName)
        ? $"#{Id} — {Subject}"
        : $"#{Id} — {Subject}  ·  {ProjectName}";
}

/// <summary>
/// Une activité de temps autorisée pour un work package (Développement, Réunion, …).
/// </summary>
public sealed record Activity(string Href, string Name)
{
    public override string ToString() => Name;
}
