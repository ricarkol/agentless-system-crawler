
pathArray = window.location.href.split('/');
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;
var firstLoad= true;
var tableRef = null;
var modalTableRef = null;

var selectedRuleGroup = "all";

var openid = null;
var apikey = null;
var tenant = null;

$(document).ready(function(){
	$.when(
  		setOpenId()
	).done(function() {
		setTopNavigator();
  		buildGroupTree();
		rootNodeClickHandler();
		buildTable();
		buildModalTable();
		getRules();
	});
});


/** Top Navigation *******************************************************/

function setTopNavigator(){
	$("#logout").on('click',function(event){
        event.preventDefault();
        event.stopPropagation();

        $.removeCookie("openid");
        $.removeCookie("tenant");
		$.removeCookie("namespace");
		$.removeCookie("timestamp");

        window.location.href = 'login.html';
	});

	$("#hellotxt").html("Hello <b>" + openid + "</b>");

	if(openid == "ibm_admin"){
		$("#tenantdd").removeClass("hidden");
		$("#sidebar li").removeClass("hidden");

		tenant = $.cookie("tenant");
		if(tenant != null){
			$("#tenantdd > a > b").text(tenant);
		}

		var url = protocol + "/api/tenants?openid=" + openid;

		$.ajax({
			type : 'GET',
			url : url,
			dataType : "json", 
			contentType : "application/json",
			success : function(data){

				$.each(data, function(i){
					$("#tenantdd ul").append('<li><a href="#">' + data[i].name + '</a></li>');
				})

				$("#tenantdd ul li a").on("click", function(event){
					var selectedTenant = $(this).text();
					$(this).parents().find("a > b").text(selectedTenant);

					$.cookie("tenant", selectedTenant);
					tenant = selectedTenant;

					buildGroupTree();
					$(".rootnode").click();
				});
			},
			error : function(xhr, status, error) {
					console.log(status);
			}
		});    	
	}
}


function setOpenId(){
	var dfd = $.Deferred();

	openid = $.cookie("openid");
	if(openid == null){
	  	window.location.href = 'login.html';
	  	dfd.reject();
	} else {
		dfd.resolve();
	}

	return dfd.promise();
}


/** Rule group tree view ********************************************/

function childNodeClickHandler() {
	$(".treenode").on('click',function(event){
        event.preventDefault();
        event.stopPropagation();

        $(".treenode").removeClass("active");
        $(".rootnode").removeClass("active");
        $(this).addClass("active");

        var groupname = $(this).text()
        var groupid = $(this).attr("href");

        $("#right-title").html("<h5><b>" + groupname + "</b></h5>");
        
		$(".tablebtn").removeClass("hidden");
		$("#gnameinput").addClass("hidden");

		if(!$(this).hasClass("default")){
			$("#removeGroupBtn").removeAttr("disabled");
		}
       	selectedRuleGroup = groupid;
       	refresh();

        return false;
    });
}


function rootNodeClickHandler() {
	$(".rootnode").on('click',function(event){
        event.preventDefault();
        event.stopPropagation();

        $(".treenode").removeClass("active");
        $(".rootnode").removeClass("active");
        $(this).addClass("active");

        $("#right-title").html("<h5><b>" + $(this).text() + "</b></h5>");
        if(!$("#gnameinput").hasClass("hidden")) {
        	$("#gnameinput").addClass("hidden");
        }

        if(!$("#gsetting-save").hasClass("hidden")) {
        	$("#gsetting-save").addClass("hidden");
       	}

		$(".tablebtn").removeClass("hidden");
		$("#gnameinput").addClass("hidden");
		$("#removeGroupBtn").prop("disabled", true);

       	selectedRuleGroup = "all";
       	refresh();

        return false;
    });
}


function createGroup(){
	$("#right-title").html("<h5><b>Create New Group</b></h5>");

	$("#gnameinput").removeClass("hidden");
	$("#gsetting-save").removeClass("hidden");

	$(".tablebtn").addClass("hidden");
}


function removeGroup(){
	var groupname = $('.treenode[href="' + selectedRuleGroup + '"]').text();
	if(confirm("Are you sure you want to delete rule group: " + groupname + "?")){

		var url = protocol + "/api/groups/" + selectedRuleGroup + "?openid=" + openid;
		if(tenant != null){
			url = url + "&tenant=" + tenant;
		}

		$.ajax({
			type : "DELETE",
			url : url,
			success : function() {
				buildGroupTree();
				$(".rootnode").click();
			},
			error : function(xhr, status, error) {
				console.log(status);
			}
		}); 			
	}
}


function buildGroupTree(){
	$('#group-view ul ul').html("");

	var url = protocol + "/api/services/get_groups?openid=" + openid;

	if(tenant != null){
		url = url + "&tenant=" + tenant;
	}

	$.ajax({
		type : "GET",
		contentType : "application/json; charset=utf-8",
		url : url,
		dataType : 'json',
		success : function(data) {
			$.each(data, function(){
				var listring = '<li><a href="' + this.id + '" class="treenode';
				if(this.default){
					listring = listring + " default";
				}
				listring = listring + '">' + this.name + "</a></li>";					
				$('#group-view ul ul').append(listring);
			});
			childNodeClickHandler();

		},
		error : function(xhr, status, error) {
			console.log(status);
		}
	}); 	
}


/* Table ****************************************************************************/
function buildTable(){
	
	tableRef = $("#dtable").dataTable({    
		"aoColumns": [       		              		
          	{"mData": "checkbox", "bSortable": false, "width": "13px","sClass": "checkvm"},     
      		{"mData": "rule_name" },      
      		{"mData": "section_name"},      
      		{"mData": "script_path"},      
      		{"mData": "description"},
      		{"mData": "long_description"} 
		],
		"paging": false,
	    "aData": null,
	    "scrollY": "450px",
	    "order": [[ 1, "asc" ]],
		"scrollCollapse": false,
		"oLanguage": {
		    "sEmptyTable":     "No records found",
		    "sLoadingRecords": "Loading...",
		    "sProcessing": "DataTables is currently busy"
		},			

		"dom": '<"row" <"col-lg-6"<"upper-left text-left">><"col-lg-6"<"upper-right text-right"lf>>><"datatable-scroll"t><"row"<"col-lg-6"<"text-left"i>><"col-lg-3 text-center"p><"col-lg-3"<"lower-right text-right">>>'
		
	});
	
	$("div.upper-left").html('<button type="button" class="tablebtn btn btn-default btn-md" onclick="addRules()">Add rule</button>&nbsp;&nbsp;'
							 +'<button type="button" onclick="removeRules()" class="tablebtn btn btn-default">Remove rules</button>&nbsp;&nbsp;'
							 +'<button type="button" class="tablebtn btn btn-default btn-md" onclick="refresh()"><i class="fa fa-refresh"></i></button>');	
	
}


function buildModalTable(){
	
	modalTableRef = $("#addtable").dataTable({    
		"aoColumns": [       		              		
          	{"mData": "checkbox", "bSortable": false, "width": "13px","sClass": "checkvm"},     
      		{"mData": "rule_name" },      
      		{"mData": "section_name"},      
      		{"mData": "script_path"},      
      		{"mData": "description"},
      		{"mData": "long_description"} 
		],
		"paging": false,
	    "aData": null,
	    "scrollY": "400px",
	    "order": [[ 1, "asc" ]],
		"scrollCollapse": true,
		"oLanguage": {
		    "sEmptyTable":     "No records found",
		    "sLoadingRecords": "Loading...",
		    "sProcessing": "DataTables is currently busy"
		},			

		"dom": '<"row" <"col-lg-1"<"upper-left text-left">><"col-lg-11"<"upper-right text-right"lf>>><"datatable-scroll"t><"row"<"col-lg-6"<"text-left"i>><"col-lg-3 text-center"p><"col-lg-3"<"lower-right text-right">>>'
		
	});
}


function callShowResult(data) {

	//setLabels();

	var message = "No rule available.";

	var flag = 0;
	var dataFound = false;
	var iTotalRecords = 0;
	var iTotalDisplayRecords = 0;
	var data1 = '{"sEcho": 1, "iTotalRecords": 2, "iTotalDisplayRecords":2,"aaData":[';

	$("#addtable tbody").find(".hidden").removeClass("hidden");

	$.each(data, function(object, Object) {

		if (data == "") {
			console.log(messge);
			message = "No rule available.";
			$('#errorDiv').addClass("alert alert-info");
			$('#errorDiv').html(
					"<strong>Information. </strong>No rule available.");
			flag = 1;

		} else if (data != null) {

			if (Object.Message != null) {
				message = Object.Message;
				console.log(message);
				$('#errorDiv').addClass("alert alert-danger");
				$('#errorDiv').html("<strong>Error. </strong>" + message);

				flag = 1;
			} else {
				dataFound = true;

				data1 = data1 + '{"checkbox":'+ '"<input type=checkbox class=checkvm id =checkvmid value='+ Object.id + '> </input>"' +",";
				data1 = data1 + '"rule_name":' + '"' + Object.name + '"' + ",";
				data1 = data1 + '"section_name":' + '"' + Object.rule_group_name + '"' + ",";
				data1 = data1 + '"script_path":' + '"' + Object.script_path + '"' + ",";
				data1 = data1 + '"description":' + '"' + Object.description + '"' + ",";
				data1 = data1 + '"long_description":' + '"?"' + "},";

				if(selectedRuleGroup != "all"){
					$("#addtable tbody td:contains(" + Object.name + ")").parent().addClass("hidden");
				}
				
			}

		}

	});
	//console.log("data1 " + data1);

	if (dataFound) {
		data1 = data1.slice(0, data1.lastIndexOf(","))
				+ data1.substring(data1.lastIndexOf(",") + 1);
	}

	if (flag == 0 && !dataFound) {
		message = "No rule available.";
		$('#errorDiv').addClass("alert alert-info");
		$('#errorDiv').html("<strong>Information </strong>No rule available.");
	}

	data1 = data1 + "]}";

	//console.log("compliance status:" + data1);
	var da = JSON.parse(data1);
	da.iTotalRecords = iTotalRecords;
	da.iTotalDisplayRecords = iTotalDisplayRecords;

	if (da.aaData.length) {
		tableRef.fnAddData(da.aaData);
		var oFeatures = tableRef.fnSettings();
		oFeatures.oLanguage.sEmptyTable = "No records found";
	} else {
		tableRef.fnClearTable();
		var oFeatures = tableRef.fnSettings();
		oFeatures.oLanguage.sEmptyTable = "No records found";
	}
	tableRef.fnDraw();

	if(selectedRuleGroup == "all"){
		if (da.aaData.length) {
			modalTableRef.fnAddData(da.aaData);
			var oFeatures = modalTableRef.fnSettings();
			oFeatures.oLanguage.sEmptyTable = "No records found";
		} else {
			modalTableRef.fnClearTable();
			var oFeatures = modalTableRef.fnSettings();
			oFeatures.oLanguage.sEmptyTable = "No records found";
		}
		modalTableRef.fnDraw();
	}

	popupRules();

}


function getRules() {

	tableRef.fnClearTable();

	var oFeatures = tableRef.fnSettings();
	oFeatures.bProcessing  = true;
	oFeatures.bServerSide = true;
	
	oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
	tableRef.fnDraw();

	if(selectedRuleGroup == "all"){
		modalTableRef.fnClearTable();

		var oFeatures = modalTableRef.fnSettings();
		oFeatures.bProcessing  = true;
		oFeatures.bServerSide = true;
		
		oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
		modalTableRef.fnDraw();
	}

	var url = protocol + "/api/services/get_tenant_rules?openid=" + openid;
	if(tenant != null){
		url = url + "&tenant=" + tenant;
	}
	if(selectedRuleGroup != "all"){
		url = url + "\&group=" + selectedRuleGroup;
	}

	//console.log(url);
	
	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : callShowResult,

	});    	

}


function popupRules() {

	var url = protocol + "/api/services/get_rule_descriptions?openid=" + openid;

	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : function(data){

			var ruleDescription = data;

			$('#dtable > tbody > tr').each(function () {

				var self = $(this);

		        self.find(':nth-child(6)').balloon({
	            	contents: function() {
		                var ruleid = self.find(':nth-child(2)').text(); 
		                var content = "";

		                $.each(ruleDescription, function(key, value){
		                	if (key == ruleid) {
		                		content = value;
		                		return false;
		                	}
		                });

		                return content;
             		}	
     			})
    		});
		},
		error:function(){console.log('Miss..');}

	});    	

}


function checkAllRules(tablename, checkall) {
	
	//var checkvms = document.getElementsByTagName('input');
	var checkvms = $('#' + tablename).find('input');
	for ( var i = 0; i < checkvms.length; i++) {
		if (checkvms[i].type == 'checkbox') {
			checkvms[i].checked = checkall.checked;
		}
	}
}


function updateRulesInGroup(requestBody){
	var url = protocol + "/api/services/set_tenant_rules?openid=" + openid + "&group=" + selectedRuleGroup;
	if(tenant != null){
		url = url + "&tenant=" + tenant;
	}

	$.ajax({
		type : "PUT",
		url : url,
		data : requestBody,
		contentType : "application/json",
		success : function(data) {
			$("#manageModal").modal('hide');
			$("#meButton").button('reset');
			$('#meButton').prop('disabled', false);

			refresh();
			$('#error_div').addClass("alert alert-success");
			$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Success.</strong>');	
		},
		error : function(jqXHR, textStatus, errorThrown) {
			console.log(textStatus, errorThrown);
			$('#error_div').addClass("alert alert-danger");
			$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Error.</strong>' + textStatus);
		}
			
	});	
}


function addRules(){
	if(selectedRuleGroup == "all"){
		uploadRuleScript();
	}else{
		addRulesFromList();
	}
}


function addRulesFromList(){

	$("#manageModal").modal('show');
 	$("#meButton").button('reset'); 
	$('#meButton').prop('disabled', false);			

 	$("#meButton").unbind();
    $("#meButton").click(function() {
		
		$(this).button('loading');

	   	var rule_count = 0;
		var requestBody = "[";

		//Get exist rule
		$('#dtable td .checkvm').each(function(){
			var checkedValue = $(this).val();

			if (rule_count ==  0) {	
				requestBody = requestBody + '"' + checkedValue + '"';
			} else {
				requestBody = requestBody + ', "' + checkedValue + '"';
			}
			rule_count++;
		});

		//Get added rule
		$('#addtable td .checkvm:checked').each(function(){
			var checkedValue = $(this).val();
			var checkedName = $(this).parent().next().text();

			if (rule_count ==  0) {	
				requestBody = requestBody + '"' + checkedValue + '"';
			} else {
				requestBody = requestBody + ', "' + checkedValue + '"';
			}
			rule_count++;
		});

		requestBody = requestBody + ']';

		//console.log(requestBody);
		updateRulesInGroup(requestBody);
		
	});
	
	$("#modalcancel").unbind();
	$("#modalcancel").click(function() {			
					
	});
}


function uploadRuleScript() {

	$("#scriptfile").click();
	$("#scriptfile").unbind('change');
	$("#scriptfile").change( function(event) {
		var fd = new FormData();

    	if ( $("#scriptfile").val() !== '' ) {
      		fd.append( "rule_zip", $("#scriptfile").prop("files")[0] );
    	}

    	var postData = {
		    type : "POST",
		    data : fd,
		    processData : false,
		    contentType : false
	    };

	    var url = protocol + "/api/rules?openid=" + openid;
	    if(tenant != null){
			url = url + "&tenant=" + tenant;
		}

	    $.ajax( url, postData ).done(function(text){
	    	refresh();
	    	$('#error_div').addClass("alert alert-success");
			$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Success.</strong> You have uploaded ' + $("#scriptfile").val() + "." );		
        }).fail(function(jqXHR, textStatus, errorThrown){
	    	$('#error_div').addClass("alert alert-danger");
			$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Failed.</strong> ' + textStatus);	
        });
		
	});
	
}


function removeRules(){
	if(selectedRuleGroup == "all"){
		removeRuleScipt();
	}else{
		removeRulesFromList();
	}
}


function removeRulesFromList(){
	var rule_count = 0;
	var requestBody = "[";

	$('#dtable td .checkvm:not(:checked)').each(function(){
		var checkedValue = $(this).val();
		var checkedName = $(this).parent().next().text();

		if (rule_count ==  0) {	
			requestBody = requestBody + '"' + checkedValue + '"';
		} else {
			requestBody = requestBody + ', "' + checkedValue + '"';
		}
		rule_count++;
	});

	requestBody = requestBody + ']';

	if (rule_count == $("#dtable tbody").children().length) {
		$('#error_div').addClass("alert alert-danger");
		$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Error.</strong> No rules are selected.');

		return;
	} 

	updateRulesInGroup(requestBody);
}


function removeRuleScipt() {
	var rule_count = 0;
	var requestBody = "[";
	var messageBody = "";

	$('#dtable td .checkvm:checked').each(function(){
		var checkedValue = $(this).val();
		var checkedName = $(this).parent().next().text();

		if (rule_count ==  0) {	
			requestBody = requestBody + '"' + checkedValue + '"';
			messageBody = messageBody + '"' + checkedName + '"';
		} else {
			requestBody = requestBody + ', "' + checkedValue + '"';
			messageBody = messageBody + '"' + checkedName + '"';
		}
		rule_count++;
	});

	requestBody = requestBody + ']';
	
	console.log("Selected rules: " + requestBody);

	if (rule_count == 0) {
		$('#error_div').addClass("alert alert-danger");
		$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Error.</strong> No rules are selected.');

		return;
	} 

	if(confirm("Are you sure you want to delete rules: " + messageBody + "?")){
		var url = protocol + "/api/rules/bulk_delete?openid=" + openid;
		if(tenant != null){
			url = url + "&tenant=" + tenant;
		}

		$.ajax({
			type : "DELETE",
			contentType : "application/json; charset=utf-8",
			data: requestBody,
			url : url,
			success : function() {
				refresh();
				$('#error_div').addClass("alert alert-success");
				$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Success.</strong> Remove ' + messageBody);
			},
			error : function(xhr, status, error) {
				$('#error_div').addClass("alert alert-danger");
				$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Failed.</strong> ' + status);
			}
		}); 			
	}
}


/**Save or Cancel rule group settings***************************/

function cancelAddGroup(){
	$(".rootnode").click();
	$("#group-name").val("");
}


function sendGroupDef(){
	var requestBody = "{";
	var groupname = $("#group-name").val();

	if(groupname == ""){
		alert("Please input group name.");
		return;
	} 

	requestBody = requestBody + "\"name\":\"" + groupname + "\"";

	var rule_count = 0;
	var checkedRules = "";

	$('#dtable td .checkvm:checked').each(function(){
		var checkedValue = $(this).val();

		if (rule_count ==  0) {	
			checkedRules = checkedRules + '"' + checkedValue + '"';
		} else {
			checkedRules = checkedRules + ', "' + checkedValue + '"';
		}
		rule_count++;
	});
	
	if (rule_count > 0) {
		requestBody = requestBody + ",\"rule_id\":[" + checkedRules + "]";
	}

	requestBody = requestBody + "}";

	console.log(requestBody);

	var url = protocol + "/api/groups?openid=" + openid;
	
	if(tenant != null){
		url = url + "&tenant=" + tenant;
	}

	$.ajax({
		type : "POST",
		url : url,
		data : requestBody,
		contentType : "application/json",
		success : function(data) {
			buildGroupTree();
			$(".rootnode").click();
			$("#group-name").val("");
			$('#error_div').addClass("alert alert-success");
			$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Success.</strong> You have created ' + data.name + "." );	
		},
		error : function(jqXHR, textStatus, errorThrown) {
			console.log(textStatus, errorThrown);
			$('#error_div').addClass("alert alert-danger");
			$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Error.</strong>' + textStatus);
		}		
	});

}


function refresh(){
	
	$("#error_div").removeClass("alert alert-danger alert-success");
	$("#error_div").removeClass("alert alert-danger alert-danger");
    $("#error_div").empty();
    numberOfActions = 0;
		
	tableRef.fnClearTable();

	var oFeatures = tableRef.fnSettings();
	oFeatures.bProcessing  = true;
	oFeatures.bServerSide = true;
	
	oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
	tableRef.fnDraw();
	
	getRules();
}
