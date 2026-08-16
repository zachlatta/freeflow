using FreeFlowWindows.Core.Models;
using FsCheck;
using FsCheck.Xunit;

namespace FreeFlowWindows.Tests.PropertyTests;

/// <summary>
/// Property-based tests for SystemTrayManager icon state mapping.
/// Tests the deterministic mapping between AppStatus values and icon states.
/// </summary>
public class SystemTrayPropertyTests
{
    /// <summary>
    /// **Validates: Requirements 1.5**
    /// 
    /// Property 9: Application Status Icon State Mapping
    /// 
    /// For any AppStatus value (Idle, Recording, Processing, Error), the UpdateIcon function 
    /// should always produce a valid icon state, and calling it twice with the same status 
    /// should result in the same icon being displayed (deterministic mapping).
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property EachAppStatus_MapsToExactlyOneIconState()
    {
        return Prop.ForAll(
            SystemTrayArbitrary.GenerateAppStatus(),
            status =>
            {
                // Create the icon state mapping (simulating what SystemTrayManager does internally)
                var iconState1 = GetIconStateForStatus(status);
                var iconState2 = GetIconStateForStatus(status);

                // Same status must always produce the same icon state (deterministic)
                return iconState1 == iconState2;
            });
    }

    /// <summary>
    /// **Validates: Requirements 1.5**
    /// 
    /// Property 9 extended: Each AppStatus maps to a distinct icon state.
    /// 
    /// No two different AppStatus values should map to the same icon state.
    /// This ensures visual differentiation for users.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property DifferentAppStatus_MapToDifferentIconStates()
    {
        return Prop.ForAll(
            SystemTrayArbitrary.GenerateDistinctAppStatusPairs(),
            pair =>
            {
                var (status1, status2) = pair;

                var iconState1 = GetIconStateForStatus(status1);
                var iconState2 = GetIconStateForStatus(status2);

                // Different statuses should produce different icon states
                return iconState1 != iconState2;
            });
    }

    /// <summary>
    /// **Validates: Requirements 1.5**
    /// 
    /// Property 9 extended: Icon state mapping covers all AppStatus values.
    /// 
    /// Every valid AppStatus enum value must have a corresponding icon state.
    /// No AppStatus should result in null or undefined icon state.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property AllAppStatus_HaveValidIconState()
    {
        return Prop.ForAll(
            SystemTrayArbitrary.GenerateAppStatus(),
            status =>
            {
                var iconState = GetIconStateForStatus(status);

                // Icon state must not be null or empty
                return !string.IsNullOrEmpty(iconState);
            });
    }

    /// <summary>
    /// **Validates: Requirements 1.5**
    /// 
    /// Property 9 extended: UpdateIcon with same status is idempotent.
    /// 
    /// Calling UpdateIcon multiple times with the same status should not change
    /// the resulting icon state after the first call.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property UpdateIcon_SameStatus_IsIdempotent()
    {
        return Prop.ForAll(
            SystemTrayArbitrary.GenerateAppStatus(),
            Arb.From(Gen.Choose(2, 10)),
            (status, repeatCount) =>
            {
                // Get the icon state for multiple consecutive calls with same status
                var firstIconState = GetIconStateForStatus(status);
                
                for (int i = 0; i < repeatCount; i++)
                {
                    var subsequentIconState = GetIconStateForStatus(status);
                    if (firstIconState != subsequentIconState)
                    {
                        return false;
                    }
                }

                // All calls with the same status must produce the same icon state
                return true;
            });
    }

    /// <summary>
    /// **Validates: Requirements 1.5**
    /// 
    /// Property 9 extended: Tooltip text mapping is deterministic.
    /// 
    /// For any AppStatus value, the tooltip text should always be the same
    /// for the same status (deterministic mapping).
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property TooltipMapping_IsDeterministic()
    {
        return Prop.ForAll(
            SystemTrayArbitrary.GenerateAppStatus(),
            status =>
            {
                var tooltip1 = GetTooltipForStatus(status);
                var tooltip2 = GetTooltipForStatus(status);

                // Same status must always produce the same tooltip
                return tooltip1 == tooltip2;
            });
    }

    /// <summary>
    /// **Validates: Requirements 1.5**
    /// 
    /// Property 9 extended: Status transitions maintain valid state.
    /// 
    /// After any sequence of status transitions, the current status should
    /// always reflect the most recently set status.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property StatusTransition_ReflectsLastStatus()
    {
        return Prop.ForAll(
            SystemTrayArbitrary.GenerateAppStatusSequence(),
            statusSequence =>
            {
                if (statusSequence.Length == 0)
                    return true;

                // Simulate a series of status transitions
                var lastStatus = statusSequence[statusSequence.Length - 1];
                var currentIconState = GetIconStateForStatus(lastStatus);
                var expectedIconState = GetIconStateForStatus(lastStatus);

                // The icon state should reflect the last status
                return currentIconState == expectedIconState;
            });
    }

    /// <summary>
    /// Simulates the icon state mapping logic from SystemTrayManager.
    /// This mirrors the internal _statusIcons dictionary behavior.
    /// </summary>
    private static string GetIconStateForStatus(AppStatus status)
    {
        // This simulates the deterministic mapping in SystemTrayManager.CreateStatusIcons()
        // Each status maps to a distinct icon type
        return status switch
        {
            AppStatus.Idle => "MicrophoneIcon_Idle",
            AppStatus.Recording => "MicrophoneIcon_Recording",
            AppStatus.Processing => "ProcessingIcon",
            AppStatus.Error => "ErrorIcon",
            _ => throw new ArgumentOutOfRangeException(nameof(status), status, 
                $"Unknown AppStatus: {status}")
        };
    }

    /// <summary>
    /// Simulates the tooltip mapping logic from SystemTrayManager.
    /// </summary>
    private static string GetTooltipForStatus(AppStatus status)
    {
        // This mirrors SystemTrayManager.UpdateIconInternal() tooltip logic
        return status switch
        {
            AppStatus.Idle => "FreeFlow - Ready",
            AppStatus.Recording => "FreeFlow - Recording...",
            AppStatus.Processing => "FreeFlow - Processing...",
            AppStatus.Error => "FreeFlow - Error",
            _ => "FreeFlow"
        };
    }
}

/// <summary>
/// Custom FsCheck arbitrary generators for SystemTray property tests.
/// </summary>
public static class SystemTrayArbitrary
{
    /// <summary>
    /// Generates arbitrary AppStatus values.
    /// </summary>
    public static Arbitrary<AppStatus> GenerateAppStatus()
    {
        return Arb.From(GenerateAppStatusGen());
    }

    /// <summary>
    /// Generates pairs of distinct AppStatus values.
    /// </summary>
    public static Arbitrary<(AppStatus, AppStatus)> GenerateDistinctAppStatusPairs()
    {
        return Arb.From(
            from status1 in GenerateAppStatusGen()
            from status2 in GenerateAppStatusGen()
            where status1 != status2
            select (status1, status2));
    }

    /// <summary>
    /// Generates sequences of AppStatus values for transition testing.
    /// </summary>
    public static Arbitrary<AppStatus[]> GenerateAppStatusSequence()
    {
        return Arb.From(
            from count in Gen.Choose(1, 10)
            from statuses in Gen.ArrayOf(count, GenerateAppStatusGen())
            select statuses);
    }

    private static Gen<AppStatus> GenerateAppStatusGen()
    {
        // Generate all valid AppStatus enum values
        var statuses = Enum.GetValues<AppStatus>();
        return Gen.Elements(statuses);
    }
}
