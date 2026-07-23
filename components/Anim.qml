import QtQuick
import Caelestia.Components
import Caelestia.Config

// Physics-driven replacement for what used to be a plain NumberAnimation.
//
// The enum, the `type` property and the duration mapping are unchanged, so
// every call site converts without being touched. What changed is that spatial
// types are now driven by a damped spring rather than a bezier curve, with
// constants fitted to those same curves -- zeta taken from each curve's exact
// overshoot so the visible bounce is reproduced, omega chosen to minimise the
// remaining error. Derivation and measured errors live in
// ~/namealle/claude/caelestia/spring-anims/.
//
// Three things still take the bezier path:
//   - the *Effects types, which are opacity fades: there is no momentum to
//     preserve and an underdamped spring would overshoot past 1.0
//   - any call site that sets `easing` itself, since curves like standardAccel
//     end at maximum velocity and a spring always decelerates into its target
//   - everything, when Tokens.anim.springs.enabled is false
SpringAnim {
    id: root

    enum Type {
        StandardSmall = 0,
        Standard,
        StandardLarge,
        StandardExtraLarge,
        EmphasizedSmall,
        Emphasized,
        EmphasizedLarge,
        EmphasizedExtraLarge,
        FastSpatial,
        DefaultSpatial,
        SlowSpatial,
        FastEffects,
        DefaultEffects,
        SlowEffects
    }

    property int type: Anim.DefaultSpatial

    readonly property bool isEffects: type >= Anim.FastEffects
    readonly property var springs: Tokens.anim.springs

    // omega is stored per family as a dimensionless omega*T, so dividing by the
    // duration recovers the frequency. That is what makes the 23 call sites
    // with an explicit `duration:` keep meaning what they meant under the
    // bezier: a shorter duration yields a proportionally stiffer spring.
    readonly property real omegaT: {
        if (!springs)
            return 0;
        if (type === Anim.FastSpatial)
            return springs.expressiveFastSpatialOmegaT;
        if (type === Anim.DefaultSpatial)
            return springs.expressiveDefaultSpatialOmegaT;
        if (type === Anim.SlowSpatial)
            return springs.expressiveSlowSpatialOmegaT;
        if (type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge)
            return springs.emphasizedOmegaT;
        return springs.standardOmegaT;
    }

    physics: !isEffects && (springs?.enabled ?? false)

    zeta: {
        if (!springs)
            return 1;
        if (type === Anim.FastSpatial)
            return springs.expressiveFastSpatialZeta;
        if (type === Anim.DefaultSpatial)
            return springs.expressiveDefaultSpatialZeta;
        if (type === Anim.SlowSpatial)
            return springs.expressiveSlowSpatialZeta;
        if (type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge)
            return springs.emphasizedZeta;
        return springs.standardZeta;
    }

    omega: root.duration > 0 ? root.omegaT * 1000 / root.duration : 0

    epsilon: springs?.epsilon ?? 0.002
    epsilonFloor: springs?.epsilonFloor ?? 0.0001
    timeCapFactor: springs?.timeCapFactor ?? 5

    duration: {
        if (type < Anim.StandardSmall || type > Anim.SlowEffects)
            return Tokens.anim.durations.normal;

        if (type === Anim.FastSpatial)
            return Tokens.anim.durations.expressiveFastSpatial;
        if (type === Anim.DefaultSpatial)
            return Tokens.anim.durations.expressiveDefaultSpatial;
        if (type === Anim.SlowSpatial)
            return Tokens.anim.durations.expressiveSlowSpatial;
        if (type === Anim.FastEffects)
            return Tokens.anim.durations.expressiveFastEffects;
        if (type === Anim.DefaultEffects)
            return Tokens.anim.durations.expressiveDefaultEffects;
        if (type === Anim.SlowEffects)
            return Tokens.anim.durations.expressiveSlowEffects;

        const types = ["small", "normal", "large", "extraLarge"];
        const idx = type % 4; // 0-7 are the 4 standard types
        return Tokens.anim.durations[types[idx]];
    }

    // Deliberately `defaultEasing`, not `easing`: writing `easing` is what marks
    // a call site as having overridden the curve, and this is the type's own
    // default rather than an override. It is set for spatial types too, so that
    // flipping springs.enabled off restores exactly the original curves.
    defaultEasing: {
        if (type === Anim.FastSpatial)
            return Tokens.anim.expressiveFastSpatial;
        if (type === Anim.DefaultSpatial)
            return Tokens.anim.expressiveDefaultSpatial;
        if (type === Anim.SlowSpatial)
            return Tokens.anim.expressiveSlowSpatial;
        if (type === Anim.FastEffects)
            return Tokens.anim.expressiveFastEffects;
        if (type === Anim.DefaultEffects)
            return Tokens.anim.expressiveDefaultEffects;
        if (type === Anim.SlowEffects)
            return Tokens.anim.expressiveSlowEffects;

        if (type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge)
            return Tokens.anim.emphasized;
        return Tokens.anim.standard;
    }
}
