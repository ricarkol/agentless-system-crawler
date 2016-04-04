/**
 * Created by sastryduri on 4/23/15.
 */

angular.module('categories.overview.summary', [
    'tm.models.overview.summary'
])
    .config(function($stateProvider){

    })
    .controller('OverviewSummaryCtrl', function($stateParams){
        var overviewSummaryCtrl = this;
        overviewSummaryCtrl.summary = [
            {
                "summary_type": "namespaces",
                "total": 50000,
                "last_week": 400,
                "last_day":45
            },
            {
                "summary_type": "bookmarks",
                "total":7823,
                "last_week": 42,
                "last_day": 17
            },
            {
                "summary_type": "compliance",
                "total": 47272,
                "last_week": 344,
                "last_day":32
            }
        ];

    })
;
