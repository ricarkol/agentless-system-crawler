angular.module('tm.models.bookmarks', [])
    .service('BookmarksModel', function ($http, $q) {
        var model = this,
            bookmarks,
            diff_results,
            URLS = {
                //FETCH: 'data/cs/bookmarks2.json',
                FETCH:  '/v0/bookmarks',
                DELETE: '/v0/bookmark',
                DIFF:   '/v0/bookmark/diff',
                CREATE: '/v0/bookmark'
            };

        function extract(result) {
            console.log(result.data);
            return result.data;

        }

        function cacheDiffResults(result) {
            var raw_diff_results = extract(result);
            diff_results = [];
            for (change_type in raw_diff_results) {
                for (i = 0; i < raw_diff_results[change_type].length; i++) {
                    var r = {
                        change: change_type,
                        feature_type: raw_diff_results[change_type][i].feature_type,
                        data: JSON.stringify(raw_diff_results[change_type][i])
                    };
                    console.log(r.change);
                    diff_results.push(r);
                }
            }
            return diff_results;
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

        model.invalidateCachedBookmarks = function (){
            bookmarks = [];
        };

        model.getBookmarks = function (searchParams) {
            var deferred = $q.defer();
            if (bookmarks && bookmarks.length > 0) {
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

        model.addBookmark = function (bookmark) {
            $http.post(URLS.CREATE, bookmark).
                success(function(data, status, headers, config) {

                }).
                error(function(data, status, headers, config) {
                    alert('bookmark addition failed');
                });
        };

        model.deleteBookmark = function (bookmark) {
            var del_url = URLS.DELETE+'/' + bookmark._id;
            $http.delete(del_url).
                success(function(data, status, headers, config) {
                    var index = bookmarks.indexOf(bookmark);
                    if (index !== -1) {
                        bookmarks.splice(index, 1);
                    }

                }).
                error(function(data, status, headers, config) {
                    alert('bookmark deletion failed');
                });
        };

        model.diffBookmarks = function (bookmark1, bookmark2){
            var deferred = $q.defer();
            var diff_params = {namespace: bookmark1.namespaces,
                begin_time: bookmark1.timestamp,
                end_time:bookmark2.timestamp
            };
            
            model.diff_output = [];

            $http.get(URLS.DIFF,{params:diff_params, cache: false} ).then(function (results) {
                deferred.resolve(cacheDiffResults(results));
            });
            return deferred.promise;
        }
    }
)
;
