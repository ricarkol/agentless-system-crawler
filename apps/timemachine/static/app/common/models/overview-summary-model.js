angular.module('tm.models.overview.summary', [])
    .service('OverviewSummaryModel', function ($http, $q) {
        var model = this,
            summaryCollection,
            URLS = {
                FETCH: 'static/data/cs/overview_summary.json'
            };

        function extract(result) {
            console.log(result.data);
            return result.data;

        }

        function cacheBookmarks(result) {
            return extract(result);
        }

        model.getCloudsightSummary = function (searchParams) {
            var deferred = $q.defer();

            if (summaryCollection) {
                deferred.resolve(summaryCollection);
            } else {
                $http.get(URLS.FETCH).then(function (summaryCollection) {
                    deferred.resolve(cacheBookmarks(summaryCollection));
                });
            }
            return deferred.promise;
        }
    }
)
;
