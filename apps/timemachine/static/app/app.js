angular.module('Timemachine', [
    'ui.router',
    'mgcrea.ngStrap',
    'categories'
])
    .config(function ($stateProvider, $urlRouterProvider) {
        $stateProvider
            .state('tm', {
                url: '',
                abstract: true
            })
        ;
      $urlRouterProvider.otherwise('/');
    })
;