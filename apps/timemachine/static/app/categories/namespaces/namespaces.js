angular.module('categories.namespaces', [
    'categories.namespaces.summary',
    'categories.namespaces.timeline'
])
    .config(function($stateProvider){

        $stateProvider.state('tm.categories.namespaces', {
            url:"namespaces",
            views: {
                'summary@':{
                    controller: 'NamespacesSummaryCtrl as namespacesSummaryCtrl',
                    templateUrl: 'static/app/categories/namespaces/summary.tmpl.html'
                }
                //'timeline@':{
                //    controller: 'NamespacesTimelineCtrl as namespacesTimelineCtrl',
                //    templateUrl: 'static/app/categories/namespaces/timeline/timeline.tmpl.html'
                //}
            }
        })
    })
;
