// Standalone test for the pure search matchers (no Qt QML / moc needed).
// Compile: g++ -std=c++17 ../src/Caelestia/searchcore.cpp search_test.cpp \
//              -o /tmp/search_test $(pkg-config --cflags --libs Qt6Core)
#include "../src/Caelestia/searchcore.hpp"

#include <QStringList>
#include <cstdio>

using namespace caelestia::search;

static int failures = 0;
#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            std::printf("FAIL (line %d): %s\n", __LINE__, #cond);              \
            ++failures;                                                        \
        } else {                                                               \
            std::printf("ok: %s\n", #cond);                                    \
        }                                                                      \
    } while (0)

int main() {
    // substring: case-insensitive, input order preserved
    CHECK(substring({"Apple", "banana", "grApe"}, "ap") == QStringList({"Apple", "grApe"}));

    // substring: empty query returns the full list unchanged
    {
        QStringList in = {"a", "b", "c"};
        CHECK(substring(in, "") == in);
    }

    // fuzzy: excludes non-subsequences, includes order-preserving matches
    {
        QStringList r = fuzzy({"left arrow", "right arrow", "up"}, "arw", 200);
        CHECK(r.size() == 2);
        CHECK(!r.contains("up"));
        CHECK(r.contains("left arrow"));
        CHECK(r.contains("right arrow"));
    }

    // fuzzy: contiguous match ranks above scattered
    {
        QStringList r = fuzzy({"axbxc", "abc"}, "abc", 200);
        CHECK(r.size() == 2);
        CHECK(r.first() == "abc");
    }

    // fuzzy: word-boundary match ranks higher
    CHECK(fuzzy({"narrow", "my arrow"}, "arrow", 200).first() == "my arrow");

    // fuzzy: empty query returns the first `limit` items
    CHECK(fuzzy({"a", "b", "c"}, "", 2) == QStringList({"a", "b"}));

    if (failures == 0) {
        std::printf("\nALL PASS\n");
        return 0;
    }
    std::printf("\n%d FAILURE(S)\n", failures);
    return 1;
}
