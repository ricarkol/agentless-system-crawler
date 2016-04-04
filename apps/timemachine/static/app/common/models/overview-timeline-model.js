angular.module('tm.models.overview.timeline', [])
    .service('OverviewTimelineModel', function ($http, $q) {
        var model = this,
            bookmarks,
            URLS = {
                FETCH: 'static/data/cs/bookmarks2.json'
            };

        function extract(result) {
            console.log(result.data);
            return result.data;

        }

        function cacheBookmarks(result) {
            bookmarks = extract(result);
            return bookmarks;
        }

        function findBookmarkById(bookmarkId) {
            return _.find(bookmarks, function (bookmark) {
                return bookmark._id === bookmarkId;
            })
        }

        function findBookmarksByTags(tags) {
            return _.find(bookmarks, function (bookmark) {
                return bookmark._id === bookmarkId;
            })
        }

        function findBookmarksByNamespaces(namespaces) {
            return _.find(bookmarks, function (bookmark) {
                return bookmark._id === bookmarkId;
            })
        }

        model.getBookmarkById = function (bookmarkId) {
            var deferred = $q.defer();

            if (bookmarks) {
                deferred.resolve(findBookmark(bookmarkId));
            } else {
                model.getBookmarks().then(function () {
                    deferred.resolve(findBookmark(bookmarkId));
                });
            }
            return deferred.promise;
        }
        model.getBookmarks = function (searchParams) {
            var deferred = $q.defer();

            if (bookmarks) {
                deferred.resolve(bookmarks);
            } else {
                $http.get(URLS.FETCH).then(function (bookmarks) {
                    deferred.resolve(cacheBookmarks(bookmarks));
                });
            }
            return deferred.promise;
        }

        model.updateBookmark = function (bookmark) {
            var index = _.findIndex(bookmarks, function (b) {
                return b.id == bookmark.id;
            });
            bookmarks[index] = bookmark;
        }

        model.createBookmark = function (bookmark) {
            bookmark.id = bookmarks.length;
            bookmarks.push(bookmark);
        };

        model.deleteBookmark = function (bookmark) {
            _.remove(bookmarks, function (b) {
                return b.id == bookmark.id;
            });
        }
    }
)
;
