angular.module('categories', [
    'categories.overview.summary',
    'categories.overview.timeline',
    'categories.bookmarks',
    'categories.namespaces',
    'tm.models.bookmarks',
    'tm.models.categories',
    'tm.models.namespaces',
    'checklist-model'
])
    .config(function($stateProvider){
        $stateProvider.state('tm.categories', {
            url:"/",
            views: {
                'categories@':{
                    controller: 'CategoriesListCtrl as categoriesListCtrl',
                    templateUrl: 'static/app/categories/categories.tmpl.html'
                },
                'summary@':{
                    controller: 'OverviewSummaryCtrl as overviewSummaryCtrl',
                    templateUrl: 'static/app/categories/overview/summary/summary.tmpl.html'
                },
                'timeline@':{
                    controller: 'OverviewTimelineCtrl as overviewTimelineCtrl',
                    templateUrl: 'static/app/categories/overview/timeline/timeline.tmpl.html'
                }
            }
        })
    }).controller('CategoriesListCtrl', function CategoriesCtrl(CategoriesModel, $state){
        categoriesListCtrl = this;
        categoriesListCtrl.currentCategory="";

        CategoriesModel.getCategories()
            .then(function(result){
                categoriesListCtrl.categories = result;
            });

        categoriesListCtrl.changeTo = function changeTo(category){
            categoriesListCtrl.currentCategory = category;
            var toState = 'tm.categories.' + category.name.toLowerCase();
            $state.go(toState);
        };

        categoriesListCtrl.isCurrentCategory = function isCurrentCategory(category){
            return categoriesListCtrl.currentCategory === category;
        };

    })
;
