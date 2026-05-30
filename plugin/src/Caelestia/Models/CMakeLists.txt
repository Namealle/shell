qml_module(caelestia-models
    URI Caelestia.Models
    SOURCES
        filesystemmodel.hpp filesystemmodel.cpp
        emojimodel.hpp emojimodel.cpp
    LIBRARIES
        Qt::Gui
        Qt::Concurrent
)
