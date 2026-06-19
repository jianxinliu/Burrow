namespace BurrowWin.Services;

/// Build/run-time configuration for the Windows telemetry pipeline.
///
/// The Windows app reports to its OWN, separate Sentry + PostHog projects —
/// distinct from the macOS app — so the two platforms never share a project
/// or need a cross-platform discriminator flag, and the macOS pipeline is
/// untouched. Values are injected purely through environment variables (set
/// by the release/CI build, sourced from a gitignored secrets file), mirroring
/// how macOS injects `SENTRY_DSN` / `POSTHOG_API_KEY`.
///
/// When a value is absent — every local/dev build — the corresponding SDK is
/// never started, so telemetry is completely inert outside signed releases.
public static class TelemetryConfig
{
    public static string SentryDsn =>
        Environment.GetEnvironmentVariable("BURROWWIN_SENTRY_DSN") ?? string.Empty;

    public static string PostHogApiKey =>
        Environment.GetEnvironmentVariable("BURROWWIN_POSTHOG_API_KEY") ?? string.Empty;

    public static string PostHogHost =>
        Environment.GetEnvironmentVariable("BURROWWIN_POSTHOG_HOST") is { Length: > 0 } host
            ? host
            : "https://us.i.posthog.com";

    public static bool IsSentryConfigured => !string.IsNullOrWhiteSpace(SentryDsn);

    public static bool IsPostHogConfigured => !string.IsNullOrWhiteSpace(PostHogApiKey);
}
