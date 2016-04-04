pathArray = window.location.href.split('/');
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;

$(document).ready(function(){
	
	
});


function login(){
	var username = $("#loginform [name=username]").val();
	var password = $("#loginform [name=pass]").val();

	var url = protocol + "/api/services/do_nothing?openid=" + username;

	$.ajax({
		type : "GET",
		contentType : "application/json; charset=utf-8",
		url : url,
		dataType : 'json',
		success : function(data) {
			openid = data.current_user.identity;
			apikey = data.current_user.api_key;

			$.cookie("openid", openid);
        	window.location.href = 'groups.html';
		},
		error : function(xhr, status, error) {
			$('#error_div').addClass("alert alert-danger");
			$('#error_div').html('<strong>ERROR.</strong> The username or password is incorrect.');

			return;
		}
	});
}
