qml_module(caelestia-components
    URI Caelestia.Components
    SOURCES
        lazylistview.cpp
        wavyline.cpp
        buttonrow.cpp
        springanim.cpp
    LIBRARIES
        Qt::Quick
        # springanim.cpp derives QQuickNumberAnimation and builds a
        # QAbstractAnimationJob, both of which live in Qt's private headers --
        # there is no public API for defining a new animation type. These have
        # no source-compatibility guarantee across Qt releases, but a break
        # surfaces as a loud build failure here rather than silently at runtime.
        Qt::QuickPrivate
        Qt::QmlPrivate
)
