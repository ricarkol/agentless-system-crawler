/**
 * Created by sastryduri on 4/23/15.
 */

angular.module('categories.namespaces.summary', [
    'tm.models.namespaces'
])
    .config(function($stateProvider){


    })
    .controller('NamespacesSummaryCtrl', function($stateParams, NamespacesModel){
        var namespacesSummaryCtrl = this;
        namespacesSummaryCtrl.summary = [
            {
                "duration": "Total",
                "count": 50000
            },
            {
                "duration": "Last Week",
                "count":7823
            },
            {
                "duration": "Last Day",
                "count": 4344
            }
        ];

        namespacesSummaryCtrl.displayFind = false;
        namespacesSummaryCtrl.namespaceQuery = {};
        namespacesSummaryCtrl.namespaces = [];

        namespacesSummaryCtrl.showFind = showFind;
        namespacesSummaryCtrl.cancelFinding = cancelFinding;
        namespacesSummaryCtrl.findNamespaces = findNamespaces;

        function showFind(){
            namespacesSummaryCtrl.displayFind = true;
        };

        function cancelFinding(){
            namespacesSummaryCtrl.displayFind = false;
        };


        function findNamespaces (namespaceQuery){
            NamespacesModel.getNamespaces(namespaceQuery)
                .then(function(namespaces){
                    namespacesSummaryCtrl.namespaces = namespaces;
                    namespacesSummaryCtrl.displayedNamespaces = [].concat(namespaces);
                });
        };
    }).directive('stRatio',function(){
        return {
            link:function(scope, element, attr){
                var ratio=+(attr.stRatio);

                element.css('width',ratio+'%');

            }
        };
    })
;
