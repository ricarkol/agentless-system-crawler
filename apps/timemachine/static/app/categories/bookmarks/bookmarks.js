angular.module('categories.bookmarks', [
    'tm.models.bookmarks',
    'tm.models.bookmarks.options',
    'categories.bookmarks.summary',
    'categories.bookmarks.timeline',
    'categories.bookmarks.create',
    'categories.bookmarks.find'

])
    .config(function($stateProvider){

        $stateProvider.state('tm.categories.bookmarks', {
            url:"bookmarks",
            views: {
                'summary@':{
                    controller: 'BookmarksSummaryCtrl as bookmarksSummaryCtrl',
                    templateUrl: 'static/app/categories/bookmarks/summary.tmpl.html'
                },
                'timeline@':{
                    controller: 'BookmarksTimelineCtrl as bookmarksTimelineCtrl',
                    templateUrl: 'static/app/categories/bookmarks/timeline.tmpl.html'
                }
            }
        })
    }).controller('BookmarksOptionsCtrl', function BookmarksOptionsCtrl(BookmarksOptionsModel, $state){
        var bookmarksOptionsCtrl = this;
        BookmarksOptionsModel.getCategories()
            .then(function(result){
                bookmarksOptionsCtrl.categories = result;
            });
        bookmarksOptionsCtrl.changeTo = function changeTo(category){

            var toState = 'tm.categories.bookmarks.' + category.name.toLowerCase();
            //alert('going to' + toState);
            $state.go(toState);
        }
    })
;
