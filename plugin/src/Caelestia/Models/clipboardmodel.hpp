#pragma once

#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QString>
#include <QList>
#include <qqmlintegration.h>

namespace caelestia::models {

struct ClipboardEntry {
    QString clipId; // Either the cliphist ID or a unique UUID for pinned items
    QString content;
    bool isImage = false;
    bool isPinned = false;
};

// Internal model that holds the clipboard history and pins
class ClipboardSourceModel : public QAbstractListModel {
    Q_OBJECT

public:
    enum Roles {
        ClipIdRole = Qt::UserRole + 1,
        ContentRole,
        IsImageRole,
        IsPinnedRole
    };

    explicit ClipboardSourceModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void loadData();
    void deleteItem(const QString& clipId);
    void togglePin(const QString& clipId);
    QString getImagePath(const QString& clipId);

private:
    void loadPins();
    void savePins();
    void ensureDirectories();

    QList<ClipboardEntry> m_entries;
};

// The proxy model exposed to QML that handles filtering
class ClipboardModel : public QSortFilterProxyModel {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)

public:
    explicit ClipboardModel(QObject* parent = nullptr);

    QString query() const;
    void setQuery(const QString& query);

    Q_INVOKABLE void reload();
    Q_INVOKABLE void deleteItem(const QString& clipId);
    Q_INVOKABLE void togglePin(const QString& clipId);
    Q_INVOKABLE QString getImagePath(const QString& clipId);

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex& source_parent) const override;

signals:
    void queryChanged();

private:
    ClipboardSourceModel* m_sourceModel;
    QString m_query;
};

} // namespace caelestia::models
