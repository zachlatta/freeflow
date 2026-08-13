using FreeFlowWindows.Core.Models;
using FsCheck;
using FsCheck.Xunit;

namespace FreeFlowWindows.Tests.PropertyTests;

/// <summary>
/// Property-based tests for HotkeyBinding hash code consistency and equality contract.
/// </summary>
public class HotkeyHashCodePropertyTests
{
    /// <summary>
    /// **Validates: Requirements 3.1, 3.2**
    /// 
    /// Property 4: Hotkey Binding Hash Code Consistency
    /// 
    /// For any two HotkeyBinding objects A and B, if A.Equals(B) returns true 
    /// (same modifiers and same key), then A.GetHashCode() must equal B.GetHashCode(). 
    /// This ensures correct behavior when using hotkey bindings as dictionary keys or in hash sets.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property EqualObjects_MustHaveSameHashCode()
    {
        return Prop.ForAll(
            HotkeyHashCodeArbitrary.GeneratePairs(),
            pair =>
            {
                var (a, b) = pair;
                
                // If A equals B, then their hash codes must be equal
                if (a.Equals(b))
                {
                    return a.GetHashCode() == b.GetHashCode();
                }
                
                // If they're not equal, hash codes may or may not match (no constraint)
                return true;
            });
    }

    /// <summary>
    /// **Validates: Requirements 3.1, 3.2**
    /// 
    /// Property 4 extended: Creating two identical HotkeyBindings must have same hash code.
    /// 
    /// For any ModifierKeys and VirtualKey combination, creating two HotkeyBinding objects
    /// with the same values should always produce equal hash codes.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property IdenticalBindings_AlwaysHaveSameHashCode()
    {
        return Prop.ForAll(
            HotkeyHashCodeArbitrary.GenerateModifierKeys(),
            HotkeyHashCodeArbitrary.GenerateVirtualKey(),
            (modifiers, key) =>
            {
                // Create two identical bindings
                var a = new HotkeyBinding { Modifiers = modifiers, Key = key };
                var b = new HotkeyBinding { Modifiers = modifiers, Key = key };

                // They must be equal and have the same hash code
                return a.Equals(b) && a.GetHashCode() == b.GetHashCode();
            });
    }

    /// <summary>
    /// **Validates: Requirements 3.1, 3.2**
    /// 
    /// Equality Reflexivity: x.Equals(x) is always true.
    /// 
    /// For any HotkeyBinding, it must always be equal to itself.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property Equals_IsReflexive()
    {
        return Prop.ForAll(
            HotkeyHashCodeArbitrary.Generate(),
            binding =>
            {
                // Reflexivity: x.Equals(x) must be true
                return binding.Equals(binding);
            });
    }

    /// <summary>
    /// **Validates: Requirements 3.1, 3.2**
    /// 
    /// Equality Symmetry: If x.Equals(y) then y.Equals(x).
    /// 
    /// For any two HotkeyBindings, equality must be symmetric.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property Equals_IsSymmetric()
    {
        return Prop.ForAll(
            HotkeyHashCodeArbitrary.GeneratePairs(),
            pair =>
            {
                var (a, b) = pair;
                
                // Symmetry: if A equals B, then B must equal A
                if (a.Equals(b))
                {
                    return b.Equals(a);
                }
                
                // If A does not equal B, then B must not equal A
                return !b.Equals(a);
            });
    }

    /// <summary>
    /// **Validates: Requirements 3.1, 3.2**
    /// 
    /// Equality Transitivity: If x.Equals(y) and y.Equals(z) then x.Equals(z).
    /// 
    /// For any three HotkeyBindings, equality must be transitive.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property Equals_IsTransitive()
    {
        return Prop.ForAll(
            HotkeyHashCodeArbitrary.GenerateTriples(),
            triple =>
            {
                var (a, b, c) = triple;
                
                // Transitivity: if A equals B and B equals C, then A must equal C
                if (a.Equals(b) && b.Equals(c))
                {
                    return a.Equals(c);
                }
                
                // If the premise doesn't hold, the property is trivially true
                return true;
            });
    }

    /// <summary>
    /// **Validates: Requirements 3.1, 3.2**
    /// 
    /// Hash code consistency: Multiple calls must return same value.
    /// 
    /// For any HotkeyBinding, calling GetHashCode multiple times must always 
    /// return the same value for an unchanged object.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property GetHashCode_IsConsistent()
    {
        return Prop.ForAll(
            HotkeyHashCodeArbitrary.Generate(),
            binding =>
            {
                // Multiple calls should return the same value
                var hash1 = binding.GetHashCode();
                var hash2 = binding.GetHashCode();
                var hash3 = binding.GetHashCode();

                return hash1 == hash2 && hash2 == hash3;
            });
    }

    /// <summary>
    /// **Validates: Requirements 3.1, 3.2**
    /// 
    /// Null handling: Equals(null) must return false.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property Equals_Null_ReturnsFalse()
    {
        return Prop.ForAll(
            HotkeyHashCodeArbitrary.Generate(),
            binding =>
            {
                // Equals(null) must return false
                return !binding.Equals(null);
            });
    }

    /// <summary>
    /// **Validates: Requirements 3.1, 3.2**
    /// 
    /// Clone produces equal object with same hash code.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property Clone_ProducesEqualObjectWithSameHashCode()
    {
        return Prop.ForAll(
            HotkeyHashCodeArbitrary.Generate(),
            binding =>
            {
                var clone = binding.Clone();

                // Clone must be equal to original and have same hash code
                return binding.Equals(clone) &&
                       clone.Equals(binding) &&
                       binding.GetHashCode() == clone.GetHashCode();
            });
    }

    /// <summary>
    /// **Validates: Requirements 3.1, 3.2**
    /// 
    /// Different bindings with different values should not be equal.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property DifferentValues_NotEqual()
    {
        return Prop.ForAll(
            HotkeyHashCodeArbitrary.GenerateDistinctPairs(),
            pair =>
            {
                var (a, b) = pair;
                
                // Distinct bindings should not be equal
                return !a.Equals(b) && !b.Equals(a);
            });
    }
}

/// <summary>
/// Custom FsCheck arbitrary generators for HotkeyBinding hash code property tests.
/// </summary>
public static class HotkeyHashCodeArbitrary
{
    /// <summary>
    /// Generates arbitrary HotkeyBinding instances.
    /// </summary>
    public static Arbitrary<HotkeyBinding> Generate()
    {
        return Arb.From(GenerateHotkeyBinding());
    }

    /// <summary>
    /// Generates arbitrary ModifierKeys combinations.
    /// </summary>
    public static Arbitrary<ModifierKeys> GenerateModifierKeys()
    {
        return Arb.From(GenerateModifierKeysGen());
    }

    /// <summary>
    /// Generates arbitrary VirtualKey values.
    /// </summary>
    public static Arbitrary<VirtualKey> GenerateVirtualKey()
    {
        return Arb.From(GenerateVirtualKeyGen());
    }

    /// <summary>
    /// Generates pairs of HotkeyBinding instances (may be equal or different).
    /// </summary>
    public static Arbitrary<(HotkeyBinding, HotkeyBinding)> GeneratePairs()
    {
        return Arb.From(
            Gen.Frequency(
                // Generate identical pairs (same values)
                Tuple.Create(3, from binding in GenerateHotkeyBinding()
                                select (binding, binding.Clone())),
                // Generate potentially different pairs
                Tuple.Create(2, from a in GenerateHotkeyBinding()
                                from b in GenerateHotkeyBinding()
                                select (a, b))));
    }

    /// <summary>
    /// Generates pairs of distinct HotkeyBinding instances (different values).
    /// </summary>
    public static Arbitrary<(HotkeyBinding, HotkeyBinding)> GenerateDistinctPairs()
    {
        return Arb.From(
            from a in GenerateHotkeyBinding()
            from b in GenerateHotkeyBinding()
            where !a.Equals(b)
            select (a, b));
    }

    /// <summary>
    /// Generates triples of HotkeyBinding instances for transitivity testing.
    /// </summary>
    public static Arbitrary<(HotkeyBinding, HotkeyBinding, HotkeyBinding)> GenerateTriples()
    {
        return Arb.From(
            Gen.Frequency(
                // Generate identical triples (all equal)
                Tuple.Create(3, from binding in GenerateHotkeyBinding()
                                select (binding, binding.Clone(), binding.Clone())),
                // Generate triples where first two are equal
                Tuple.Create(2, from ab in GenerateHotkeyBinding()
                                from c in GenerateHotkeyBinding()
                                select (ab, ab.Clone(), c)),
                // Generate random triples
                Tuple.Create(1, from a in GenerateHotkeyBinding()
                                from b in GenerateHotkeyBinding()
                                from c in GenerateHotkeyBinding()
                                select (a, b, c))));
    }

    private static Gen<HotkeyBinding> GenerateHotkeyBinding()
    {
        return from modifiers in GenerateModifierKeysGen()
               from key in GenerateVirtualKeyGen()
               select new HotkeyBinding
               {
                   Modifiers = modifiers,
                   Key = key
               };
    }

    private static Gen<ModifierKeys> GenerateModifierKeysGen()
    {
        // Generate all valid combinations of modifier keys (including None)
        return from useCtrl in Arb.Generate<bool>()
               from useAlt in Arb.Generate<bool>()
               from useShift in Arb.Generate<bool>()
               from useWin in Arb.Generate<bool>()
               select (useCtrl ? ModifierKeys.Ctrl : ModifierKeys.None) |
                      (useAlt ? ModifierKeys.Alt : ModifierKeys.None) |
                      (useShift ? ModifierKeys.Shift : ModifierKeys.None) |
                      (useWin ? ModifierKeys.Win : ModifierKeys.None);
    }

    private static Gen<VirtualKey> GenerateVirtualKeyGen()
    {
        // Use all defined VirtualKey enum values
        var keys = Enum.GetValues<VirtualKey>();
        return Gen.Elements(keys);
    }
}
