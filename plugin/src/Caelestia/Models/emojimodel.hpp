#pragma once

#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QString>
#include <QList>
#include <qqmlintegration.h>

namespace caelestia::models {

struct EmojiEntry {
    QString character;
    QString name;
};

// Internal model that holds all 10,000 emojis statically.
class EmojiSourceModel : public QAbstractListModel {
    Q_OBJECT

public:
    enum Roles {
        CharacterRole = Qt::UserRole + 1,
        NameRole
    };

    explicit EmojiSourceModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

private:
    void loadData();

    QList<EmojiEntry> m_allEmojis;
};

// The proxy model exposed to QML that handles filtering and emits row animations.
class EmojiModel : public QSortFilterProxyModel {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)

public:
    explicit EmojiModel(QObject* parent = nullptr);

    QString query() const;
    void setQuery(const QString& query);

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex& source_parent) const override;

signals:
    void queryChanged();

private:
    EmojiSourceModel* m_sourceModel;
    QString m_query;
};

} // namespace caelestia::models
