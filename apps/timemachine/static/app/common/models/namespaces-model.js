angular.module('tm.models.namespaces', [])
    .service('NamespacesModel', function ($http, $q) {
        var model = this,
            namespaces,
            URLS = {
                FETCH: 'static/data/cs/namespaces.json'
            };

        function extract(result) {
            console.log(result.data);
            return result.data;
        }

        function cacheNamespaces(result) {
            namespaces = extract(result);
            return namespaces;
        }

        model.getNamespaces = function (searchParams) {
            var deferred = $q.defer();

            if (namespaces) {
                deferred.resolve(namespaces);
            } else {
                $http.get(URLS.FETCH).then(function (namespaces) {
                    deferred.resolve(cacheNamespaces(namespaces));
                });
            }
            return deferred.promise;
        }
    }
)
;
