#include "springanim.hpp"

#include <QtQml/private/qabstractanimationjob_p.h>
#include <QtQml/private/qcontinuinganimationgroupjob_p.h>
#include <QtQml/private/qqmlproperty_p.h>
#include <qpointer.h>

#include <cmath>

namespace caelestia::components {

namespace {

// Below this the spring is critically damped for practical purposes and the
// underdamped/overdamped branches both degenerate.
constexpr qreal minOmega = 0.0001;

} // namespace

// The integrator. One instance per property per transition; velocity is
// inherited from, and written back to, the owning SpringAnim.
class SpringAnimJob : public QAbstractAnimationJob {
    Q_DISABLE_COPY_MOVE(SpringAnimJob)

public:
    SpringAnimJob(SpringAnim* anim, const QQmlProperty& property)
        : m_anim(anim)
        , m_property(property) {}

    // Indefinite: a spring has no scheduled end, it stops when it has settled.
    // QContinuingAnimationGroupJob is built for exactly this and finishes once
    // every child has stopped.
    [[nodiscard]] int duration() const override { return -1; }

    qreal to = 0;
    qreal current = 0;
    qreal velocity = 0;
    qreal zeta = 1;
    qreal omega = 20;
    qreal settleEpsilon = 0.002;
    int capMs = 2000;

protected:
    void updateCurrentTime(int time) override {
        // Clamp: a stalled frame (compositor hiccup, an image decode landing)
        // must not be integrated as one huge step and fling the property.
        const qreal dt = std::min(qreal(time - m_lastTime) / 1000.0, qreal(1.0 / 30.0));
        m_lastTime = time;

        if (dt > 0)
            advance(dt);

        // Settled needs BOTH conditions. Position alone would halt the spring
        // mid-flight on the frame it happens to pass through its target at
        // speed. The velocity bound is scaled by omega to keep it dimensionally
        // consistent with the position bound.
        const bool settled =
            std::abs(current - to) < settleEpsilon && std::abs(velocity) < settleEpsilon * std::max(omega, minOmega);
        // The time cap is the backstop: anything waiting on this animation to
        // complete (ClipReader's exit callback, a ListView transition holding
        // an item) must never be left hanging by a spring that is being
        // retargeted faster than it can converge.
        const bool capped = time >= capMs;

        if (settled || capped) {
            current = to;
            velocity = 0;
            write();
            stop();
            return;
        }

        write();
    }

    void updateState(State newState, State oldState) override {
        QAbstractAnimationJob::updateState(newState, oldState);

        // Note: velocity is NOT seeded here. Children of a
        // QContinuingAnimationGroupJob are not reliably taken through
        // updateState(Running) before their first tick, so seeding here loses
        // the carry-over on a retarget. It is done in transition() instead,
        // alongside every other parameter.
        if (newState == Running && oldState != Running) {
            m_lastTime = 0;
            write();
        }
    }

private:
    // Advance the spring by dt using its exact closed-form solution.
    //
    // A damped spring with a fixed target is a linear ODE with a known
    // analytic solution, so stepping it numerically buys nothing and costs
    // accuracy: semi-implicit Euler adds artificial damping of roughly
    // omega*h/2, which at a 16ms frame and omega=20 inflates an intended
    // zeta of 0.806 to ~0.885 and throws away two thirds of the overshoot the
    // curve fit exists to reproduce. This form is exact at any dt, needs no
    // substepping, cannot go unstable or NaN at high frequencies, and is
    // cheaper than even two Euler steps.
    void advance(qreal dt) {
        const qreal d0 = current - to; // displacement from target
        const qreal v0 = velocity;
        const qreal e = std::exp(-zeta * omega * dt);

        if (zeta < 1.0 - 1e-6) {
            // Underdamped: oscillates in, overshooting on the way.
            const qreal wd = omega * std::sqrt(1.0 - zeta * zeta);
            const qreal c = std::cos(wd * dt);
            const qreal s = std::sin(wd * dt);
            current = to + e * (d0 * c + (v0 + zeta * omega * d0) / wd * s);
            velocity = e * (v0 * c - (omega * omega * d0 + zeta * omega * v0) / wd * s);
        } else if (zeta > 1.0 + 1e-6) {
            // Overdamped: two real roots, no overshoot at all.
            const qreal r = omega * std::sqrt(zeta * zeta - 1.0);
            const qreal r1 = -zeta * omega + r;
            const qreal r2 = -zeta * omega - r;
            const qreal c1 = (v0 - r2 * d0) / (r1 - r2);
            const qreal c2 = d0 - c1;
            const qreal e1 = std::exp(r1 * dt);
            const qreal e2 = std::exp(r2 * dt);
            current = to + c1 * e1 + c2 * e2;
            velocity = c1 * r1 * e1 + c2 * r2 * e2;
        } else {
            // Critically damped: the repeated-root case, where the two
            // branches above both degenerate.
            const qreal k = v0 + omega * d0;
            current = to + e * (d0 + k * dt);
            velocity = e * (v0 - omega * k * dt);
        }
    }

    void write() {
        if (m_property.isValid()) {
            // BypassInterceptor is not optional. A plain QQmlProperty::write()
            // goes through the property's interceptor, and for anything driven
            // by `Behavior on x {}` that interceptor IS the Behavior -- which
            // starts a new transition, which creates a new job, which writes
            // again. That recursion overflows the stack on the first frame.
            // DontRemoveBinding keeps the property's binding intact, matching
            // what Qt's own property animations do.
            QQmlPropertyPrivate::write(m_property, current,
                QQmlPropertyData::BypassInterceptor | QQmlPropertyData::DontRemoveBinding);
        }
        if (m_anim) {
            m_anim->m_velocities.insert(m_property, velocity);
            if (!qFuzzyCompare(m_anim->m_velocity, velocity)) {
                m_anim->m_velocity = velocity;
                emit m_anim->velocityChanged();
            }
        }
    }

    QPointer<SpringAnim> m_anim;
    QQmlProperty m_property;
    int m_lastTime = 0;
};

SpringAnim::SpringAnim(QObject* parent)
    : QQuickNumberAnimation(parent) {
    // Any write to `easing` -- including a binding at a call site -- is taken as
    // an explicit override and pins this animation to the bezier path. See the
    // property docs in the header for why that has to be so.
    //
    // The guard is essential. The bezier path applies defaultEasing by calling
    // setEasing(), which emits this very signal. Without the guard the first
    // bezier animation latches m_easingExplicit and useSpring() then returns
    // false forever -- so with springs disabled at startup they could never be
    // enabled again, and the whole feature silently did nothing.
    connect(this, &QQuickPropertyAnimation::easingChanged, this, [this] {
        if (!m_applyingDefaultEasing)
            m_easingExplicit = true;
    });
}

bool SpringAnim::physics() const {
    return m_physics;
}

void SpringAnim::setPhysics(bool physics) {
    if (m_physics == physics)
        return;

    m_physics = physics;
    emit physicsChanged();
}

qreal SpringAnim::zeta() const {
    return m_zeta;
}

void SpringAnim::setZeta(qreal zeta) {
    if (qFuzzyCompare(m_zeta, zeta))
        return;

    m_zeta = zeta;
    emit zetaChanged();
}

qreal SpringAnim::omega() const {
    return m_omega;
}

void SpringAnim::setOmega(qreal omega) {
    if (qFuzzyCompare(m_omega, omega))
        return;

    m_omega = omega;
    emit omegaChanged();
}

qreal SpringAnim::velocity() const {
    return m_velocity;
}

qreal SpringAnim::epsilon() const {
    return m_epsilon;
}

void SpringAnim::setEpsilon(qreal epsilon) {
    if (qFuzzyCompare(m_epsilon, epsilon))
        return;

    m_epsilon = epsilon;
    emit epsilonChanged();
}

qreal SpringAnim::epsilonFloor() const {
    return m_epsilonFloor;
}

void SpringAnim::setEpsilonFloor(qreal epsilonFloor) {
    if (qFuzzyCompare(m_epsilonFloor, epsilonFloor))
        return;

    m_epsilonFloor = epsilonFloor;
    emit epsilonFloorChanged();
}

qreal SpringAnim::timeCapFactor() const {
    return m_timeCapFactor;
}

void SpringAnim::setTimeCapFactor(qreal timeCapFactor) {
    if (qFuzzyCompare(m_timeCapFactor, timeCapFactor))
        return;

    m_timeCapFactor = timeCapFactor;
    emit timeCapFactorChanged();
}

QEasingCurve SpringAnim::defaultEasing() const {
    return m_defaultEasing;
}

void SpringAnim::setDefaultEasing(const QEasingCurve& defaultEasing) {
    if (m_defaultEasing == defaultEasing)
        return;

    m_defaultEasing = defaultEasing;
    emit defaultEasingChanged();
}

bool SpringAnim::useSpring() const {
    return m_physics && !m_easingExplicit && m_omega > minOmega;
}

QAbstractAnimationJob* SpringAnim::transition(
    QQuickStateActions& actions, QQmlProperties& modified, TransitionDirection direction, QObject* defaultTarget) {
    if (!useSpring()) {
        // Bezier path. The call site's own easing wins if it set one; otherwise
        // apply the curve the type maps to, flagged so the resulting
        // easingChanged is not mistaken for a call site overriding us.
        if (!m_easingExplicit && m_defaultEasing != QEasingCurve()) {
            m_applyingDefaultEasing = true;
            QQuickPropertyAnimation::setEasing(m_defaultEasing);
            m_applyingDefaultEasing = false;
        }
        return QQuickNumberAnimation::transition(actions, modified, direction, defaultTarget);
    }

    // Reuse the base class's resolution of target/property/targets/properties
    // and its ViewTransition handling; we only replace how the value is driven.
    QQuickStateActions dataActions = QQuickNumberAnimation::createTransitionActions(actions, modified, defaultTarget);
    if (dataActions.isEmpty())
        return nullptr;

    // 4.6/(zeta*omega) is the analytic time to settle within 1%; the cap is a
    // configurable multiple of it, floored so a very slow spring still gets a
    // usable window.
    const qreal settleMs = 4600.0 / (std::max(m_zeta, qreal(0.05)) * m_omega);
    const int capMs = std::max(50, int(settleMs * m_timeCapFactor));

    auto* const group = new QContinuingAnimationGroupJob;

    for (const QQuickStateAction& action : std::as_const(dataActions)) {
        if (!action.property.isValid())
            continue;

        auto* const job = new SpringAnimJob(this, action.property);

        job->to = action.toValue.toReal();

        // Start from the property's LIVE value, not action.fromValue.
        //
        // QQuickBehavior fills fromValue with the value the behaviour started
        // at, not the value the property currently holds -- so on a retarget
        // mid-flight it is stale. Trusting it teleports the property back to
        // where the previous animation began before springing to the new
        // target, which reads as a violent snap and destroys the continuity the
        // whole physics path exists to provide.
        //
        // An explicitly declared `from:` is a different matter: that is the
        // author asking to start somewhere specific (the add/remove transitions
        // do exactly this), so it wins when present.
        // Must be qualified: QQuickNumberAnimation shadows from() with a qreal
        // overload that returns 0 when unset, which is indistinguishable from a
        // deliberate `from: 0`. Only the QVariant one reports "not specified".
        const QVariant declaredFrom = QQuickPropertyAnimation::from();
        job->current = declaredFrom.isValid() ? declaredFrom.toReal() : action.property.read().toReal();

        // The momentum carry-over, and the whole reason for using physics here:
        // a retarget mid-flight resumes at the speed the motion already had
        // rather than restarting from a dead stop. m_velocities still holds the
        // outgoing job's last value at this point -- the Behavior calls
        // transition() before tearing the old animation down.
        job->velocity = m_velocities.value(action.property, 0.0);
        job->zeta = m_zeta;
        job->omega = m_omega;
        job->capMs = capMs;
        // Proportional to the distance actually being travelled, which is the
        // only way one number serves both a 2000px height and a 0->1 opacity.
        job->settleEpsilon = std::max(m_epsilonFloor, m_epsilon * std::abs(job->to - job->current));

        group->appendAnimation(job);
    }

    return group;
}

} // namespace caelestia::components
