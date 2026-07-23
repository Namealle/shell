#pragma once

#include <QtQuick/private/qquickanimation_p.h>
#include <qeasingcurve.h>
#include <qhash.h>
#include <qqmlproperty.h>

namespace caelestia::components {

class SpringAnimJob;

// A NumberAnimation that can drive its property with a damped spring instead of
// an easing curve.
//
// Why physics at all: an easing curve has to finish at a fixed instant, so an
// interruption throws away whatever velocity the motion had and restarts from a
// dead stop. In the launcher that happens constantly -- the panel's height is
// retargeted on every keystroke as the result count changes, the highlight's y
// on every arrow key. A spring keeps its momentum through a retarget and simply
// re-aims, which is the entire point of the conversion.
//
// Why it subclasses QQuickNumberAnimation rather than being a standalone
// integrator: only an Animation can be placed inside `Behavior on x {}` or a
// ListView Transition. Deriving means Qt's property resolution, ViewTransition
// plumbing and state-action machinery all work unchanged, so every existing
// call site converts without being edited.
//
// Deliberately NOT Qt's own SpringAnimation, which opens its integrator with
// `if (elapsed < 16) return; // capped at 62fps.` -- on a 175Hz display that
// drops two frames in three, and would be a visible downgrade from the
// NumberAnimation it replaces.
class SpringAnim : public QQuickNumberAnimation {
    Q_OBJECT
    QML_ELEMENT

    // When false, or when the type maps to a curve a spring cannot reproduce,
    // everything falls through to the ordinary NumberAnimation path.
    Q_PROPERTY(bool physics READ physics WRITE setPhysics NOTIFY physicsChanged)

    // The damping ratio: 1 glides in and stops dead, below 1 overshoots and
    // comes back. Alone it determines the size of the bounce.
    Q_PROPERTY(qreal zeta READ zeta WRITE setZeta NOTIFY zetaChanged)
    // Natural frequency in rad/s. The only speed knob.
    Q_PROPERTY(qreal omega READ omega WRITE setOmega NOTIFY omegaChanged)

    // The live speed of the most recently driven property, in units/second.
    // Read-only: it is the state the physics carries across a retarget, and is
    // exposed mainly so that behaviour can be asserted in tests.
    Q_PROPERTY(qreal velocity READ velocity NOTIFY velocityChanged)

    Q_PROPERTY(qreal epsilon READ epsilon WRITE setEpsilon NOTIFY epsilonChanged)
    Q_PROPERTY(qreal epsilonFloor READ epsilonFloor WRITE setEpsilonFloor NOTIFY epsilonFloorChanged)
    Q_PROPERTY(qreal timeCapFactor READ timeCapFactor WRITE setTimeCapFactor NOTIFY timeCapFactorChanged)

    // The curve used on the bezier path. Kept separate from `easing` so that
    // assigning it does not count as a call site overriding the easing: any
    // write to `easing` is taken as an explicit override and forces bezier
    // mode, because curves like standardAccel end at maximum velocity, which a
    // spring cannot do -- it always decelerates into its target.
    Q_PROPERTY(QEasingCurve defaultEasing READ defaultEasing WRITE setDefaultEasing NOTIFY defaultEasingChanged)

public:
    explicit SpringAnim(QObject* parent = nullptr);

    [[nodiscard]] bool physics() const;
    void setPhysics(bool physics);

    [[nodiscard]] qreal zeta() const;
    void setZeta(qreal zeta);

    [[nodiscard]] qreal omega() const;
    void setOmega(qreal omega);

    [[nodiscard]] qreal velocity() const;

    [[nodiscard]] qreal epsilon() const;
    void setEpsilon(qreal epsilon);

    [[nodiscard]] qreal epsilonFloor() const;
    void setEpsilonFloor(qreal epsilonFloor);

    [[nodiscard]] qreal timeCapFactor() const;
    void setTimeCapFactor(qreal timeCapFactor);

    [[nodiscard]] QEasingCurve defaultEasing() const;
    void setDefaultEasing(const QEasingCurve& defaultEasing);

signals:
    void physicsChanged();
    void zetaChanged();
    void omegaChanged();
    void velocityChanged();
    void epsilonChanged();
    void epsilonFloorChanged();
    void timeCapFactorChanged();
    void defaultEasingChanged();

protected:
    QAbstractAnimationJob* transition(QQuickStateActions& actions, QQmlProperties& modified,
        TransitionDirection direction, QObject* defaultTarget = nullptr) override;

private:
    friend class SpringAnimJob;

    [[nodiscard]] bool useSpring() const;

    bool m_physics = true;
    // Set by any write to `easing`, including from a QML binding at a call site.
    bool m_easingExplicit = false;
    // Guards the one write to `easing` we make ourselves, when applying
    // defaultEasing on the bezier path. Without it that write trips
    // m_easingExplicit via easingChanged and permanently disables the spring
    // path -- see the comment on the connect() in the constructor.
    bool m_applyingDefaultEasing = false;

    qreal m_velocity = 0.0;
    qreal m_zeta = 1.0;
    qreal m_omega = 20.0;
    qreal m_epsilon = 0.002;
    qreal m_epsilonFloor = 0.0001;
    qreal m_timeCapFactor = 5.0;

    QEasingCurve m_defaultEasing;

    // Velocity carried across retargets, keyed by the property being driven.
    // Storing the number rather than reusing the job object keeps this clear of
    // the lifetime hazards of re-parenting a live job into a second group: a
    // fresh job is created each transition and simply seeded from here.
    QHash<QQmlProperty, qreal> m_velocities;
};

} // namespace caelestia::components
