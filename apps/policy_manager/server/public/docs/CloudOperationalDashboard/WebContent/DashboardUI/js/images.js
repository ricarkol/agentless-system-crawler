
pathArray = window.location.href.split('/');
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;
var firstLoad= true;
var tableRef = null;

var compliance_status = "";
var selectedRuleGroup = "";
var defaultGroup = "";

var openid = "";
var tenant = "";

$(document).ready(function(){
	$.when(
  		setOpenId()
	).done(function() {
		setTopNavigator();
		buildTable();
		fillRuleGroupBox();
		groupSelectHandler();
		getRules();
		modalButtonHandler();
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
		$("#modalSelectTenantDiv").removeClass("hidden");


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
				var tenantSelect = $("#tenantSelect").empty();
				tenantSelect.append($("<option />").val("all").text("-- Select tenant --"));		

				$.each(data, function(i){
					$("#tenantdd ul").append('<li><a href="#">' + data[i].name + '</a></li>');
					tenantSelect.append($("<option />").val(data[i].name).text(data[i].name));
				})

				$("#tenantdd ul li a").on("click", function(event){
					var selectedTenant = $(this).text();
					$(this).parents().find("a > b").text(selectedTenant);

					$.cookie("tenant", selectedTenant);
					tenant = selectedTenant;

					getRules();
					fillRuleGroupBox();
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


/** Rule group selection ***************************************/

function groupSelectHandler(){
	$("#groupSelectBody").change(function(){
		var name = $("#groupSelectBody option:selected").text();
		var id = $("#groupSelectBody option:selected").val();
		var selectedRuleGroup = id;

		//console.log(name + "," + id);

		var isDefault = false;

		var splitedName = name.split("(Default)");
		if(splitedName[0] == defaultGroup){
			isDefault = true;
			name = defaultGroup;
		}

		if(id == "all"){
			isDefault = true;
			selectedRuleGroup = "";
		}

		getAssignedRules(name, id, isDefault);

		//TODO: Add updating namespace table
	});
}


/** Auto assign rules view *************************************/

function getAssignedRules(groupname, groupid, isDefault) {

	if(isDefault){
		$("#assignlist").html("<li>Default rule group is <b>" + defaultGroup + "</b></li>");
		return;
	}

	var url = protocol + "/api/services/get_auto_assign?openid=" + openid + "&group=" + groupid;
	if(tenant != null){
		url = url + "&tenant=" + tenant;
	}

	$.ajax({
		type : "GET",
		contentType : "application/json; charset=utf-8",
		url : url,
		dataType : 'json',
		success : function(data) {
			$("#assignlist").html("");
			if(data != null){
				$.each(data, function(i) {
					addList(data[i].left, data[i].pattern);
				});
			}
		},
		error : function(xhr, status, error) {
			console.log(status);
		}
	}); 	
}


function editDeleteHandler(){
	$(".badge-edit").filter(":last").click(function(){
		var li = $(this).parent();
		li.find("b").addClass("hidden");
		li.find("select, input").removeClass("hidden");

	});

	$(".badge-delete").filter(":last").click(function(){
		$(this).parent().addClass("hidden");
	});
}


function addList(c1, c2){

	var html = "<li><b class=\"leftb\">" + c1 + "</b><select class=\"assign-select hidden\"><option value=\"namespace\"";
	
	if(c1 == "namespace"){
		html = html + " selected";
	}

	html = html + ">namespace</option><option value=\"owner_namespace\"";

	if(c1 == "owner_namespace"){
		html = html + " selected";
	}

	html = html + ">owner namespace</option></select>&nbsp;matches <b class=\"patternb\">" + c2 + "</b><input class=\"hidden\" value=\"" + c2 + "\">&nbsp;&nbsp;<span class=\"badge badge-edit\">Edit</span><span class=\"badge badge-delete\">Delete</span></li>";

	$("#assignlist").append(html);

	editDeleteHandler();
}


function addAssignRules(){
	addList("", "");
	$("#assignlist li").filter(":last").addClass("add");
	$(".badge-edit").filter(":last").trigger("click");
}


function cancelAssignRules(){
	$("#assignlist li,b").removeClass("hidden");
	$("#assignlist select,input").addClass("hidden");
	$("#assignlist .add").remove();
}


function submitAssignRules(){

	var firstvalue = true;
	var requestBody = "[";

	$("#assignlist li").each(function(){
		if(!$(this).hasClass("hidden")){
			var left = $(this).children("select").val();
			var pattern = $(this).children("input").val();

			$(this).children(".leftb").text(left);
			$(this).children(".patternb").text(pattern);

			if(firstvalue) {
				firstvalue = false;
			} else {
				requestBody = requestBody + ",";
			}
			requestBody = requestBody + '{"left":"' + left + '","pattern":"' + pattern + '"}';
		}
	});

	requestBody = requestBody + "]";

	var url = protocol + "/api/services/set_auto_assign?openid=" + openid + "&group=" + selectedRuleGroup;
	if(tenant != null){
		url = url + "&tenant=" + tenant;
	}

	//console.log(requestBody);
	$.ajax({
		type : "PUT",
		url : url,
		data : requestBody,
		contentType : "application/json",
		success : function(data) {
			console.log("success!");
		},
		error : function(jqXHR, textStatus, errorThrown) {
			console.log(textStatus, errorThrown);
			$('#error_div').addClass("alert alert-danger");
			$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Error.</strong>' + textStatus);
		}
			
	});

	$("#assignlist li").removeClass("add");
	$("#assignlist b").removeClass("hidden");
	$("#assignlist select,input").addClass("hidden");
	$("#assignlist li.hidden").remove();
}


/** *************************************************************************/

function buildTable(){
	
	tableRef = $("#dtable").dataTable({    
		"aoColumns": [       		              		
		                  	{"mData": "checkbox", "bSortable": false, "width": "13px","sClass": "checkvm"},   
		              		{"mData": "namespace" },     
		              		{"mData": "group"},        
		              		{"mData": "auto_assigned"}, 
		              		{"mData": "assigned_time"},  
		              		{"mData": "first_crawl"},      
		              		{"mData": "latest_crawl"},  
		              		{"mData": "latest_vul_result"},   
		              		{"mData": "latest_comp_result"}
		              ],
			"paging": false,
		    "aData": null,
		    "scrollY": "450px",
		    "scrollX": true,
		    "order": [[ 1, "asc" ]],
			"scrollCollapse": false,
			"oLanguage": {
					   "sEmptyTable":     "No records found",
					   "sLoadingRecords": "Loading...",
					   "sProcessing": "DataTables is currently busy"
					   },			

			"dom": '<"row" <"col-lg-4"<"upper-left">><"col-lg-5 text-center"lf><"col-lg-3"<"upper-right text-right">>>t<"row"<"col-lg-3"<"text-left"i>><"col-lg-6 text-center"p><"col-lg-3"<"lower-right text-right">>>'
			
		});
	
	$("div.upper-right").html('<button type="button" class="btn btn-default btn-md" onclick="refresh()"><i class="fa fa-refresh"></i></button>&nbsp;&nbsp;'
							 +'<button type="button" id="updateb1" onclick="showUpdateModal()" class="btn btn-default">Change</button>');	
	
}


function callShowResult(data) {

	//setLabels();

	var message = "No rule available.";

	var flag = 0;
	var dataFound = false;
	var iTotalRecords = 0;
	var iTotalDisplayRecords = 0;
	var data1 = '{"sEcho": 1, "iTotalRecords": 2, "iTotalDisplayRecords":2,"aaData":[';

	$.each(data, function(object, Object) {

		if (data == "") {
			console.log(messge);
			message = "No rule available.";
			$('#errorDiv').addClass("alert alert-info");
			$('#errorDiv').html("<strong>Information. </strong>No rule available.");
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
				
				data1 = data1+ '{"checkbox":'+ '"<input type=checkbox class=checkvm id =checkvmid value='+ Object.namespace + '> </input>"' +",";
				data1 = data1 + '"namespace":' + '"' + Object.namespace + '"' + ",";
				data1 = data1 + '"group":' + '"' + Object.group + '"' + ",";
				data1 = data1 + '"auto_assigned":' + '"' + Object.auto_assigned + '"' + ",";
				data1 = data1 + '"assigned_time":' + '"' + Object.assigned_time + '"' + ",";
				data1 = data1 + '"first_crawl":' + '"' + Object.first_crawl + '"' + ",";
				data1 = data1 + '"latest_crawl":' + '"' + Object.latest_crawl + '"' + ",";
				var vul = Object.latest_vul_result;
				if(vul == null){
					data1 = data1 + '"latest_vul_result":' + '"null"'+ ",";
				}else{
					data1 = data1 + '"latest_vul_result":' + '"' + Object.latest_vul_result.vulnerable_packages + "/" + Object.latest_vul_result.total_packages + '"'+ ",";
				}
				data1 = data1 + '"latest_comp_result":' + '"' + Object.latest_comp_result + '"' + "},";
				
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

//	console.log("compliance status:" + data1);
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

	changeFailColor();

}

function changeFailColor() {

	$('#dtable > tbody > tr').each(function () {

		var vul_value = $(this).find(':nth-child(9)');
        if (vul_value.text() == "FAIL" || vul_value.text() == "Fail" ) {
        	vul_value.attr('class', 'fail');
        }

        var comp_value = $(this).find(':nth-child(8)');
        if (!comp_value.text().startsWith("0/") ) {
        	comp_value.attr('class', 'fail');
        }
    });
	
}


function getRules() {

	tableRef.fnClearTable();

	var oFeatures = tableRef.fnSettings();
	oFeatures.bProcessing  = true;
	oFeatures.bServerSide = true;
	
	oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
	tableRef.fnDraw();

	var url = protocol + "/api/services/get_image_status_per_tenant?openid=" + openid;
	if(tenant != null){
		url = url + "&tenant=" + tenant;
	}

	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : callShowResult,

	});    	

}


function checkAllRules(checkall) {
	
	var checkvms = document.getElementsByTagName('input');
	for ( var i = 0; i < checkvms.length; i++) {
		if (checkvms[i].type == 'checkbox') {
			checkvms[i].checked = checkall.checked;
		}
	}
}


function fillRuleGroupBox() {	

	var url = protocol + "/api/services/get_groups?openid=" + openid;
	if(tenant != null){
		url = url + "&tenant=" + tenant;
	}
	
	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json",
		contentType : "application/json",
		success : function(data) {
			//console.log(data);
			
			var ruleGroupSelect = $(".ruleGroupSelect").empty();
			ruleGroupSelect.append($("<option />").val("all").text("-- Select rule group --"));		

			$.each(data, function(index, Object) {
				var text = Object.name;
				if(Object.default){
					defaultGroup = text;
					text = text  + "(Default)";
					getAssignedRules(Object.name, Object.id, true);
				}
				ruleGroupSelect.append($("<option />").val(Object.id).text(text));
			});
		}

	});
}


function setSelectedRuleGroup(id)
{
	selectedRuleGroup = null;
	var ruleGroupSelect = document.getElementById(id);
	selectedRuleGroup = ruleGroupSelect.options[ruleGroupSelect.selectedIndex].value;	
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
	
	fillRuleGroupBox();
	getRules();
	
}


/** Manage modal ***********************************************************/


function setRuleGroup(selectedTenant) {

	var url = protocol + "/api/services/get_groups?openid=" + openid + "&tenant=" + selectedTenant.value;
	
	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json",
		contentType : "application/json",
		success : function(data) {
			//console.log(data);
			
			var ruleGroupSelect = $("#groupSelectModal").empty();
			ruleGroupSelect.append($("<option />").val("all").text("-- Select rule group --"));		

			$.each(data, function(index, Object) {
				var text = Object.name;
				if(Object.default){
					defaultGroup = text;
					text = text  + "(Default)";
					getAssignedRules(Object.name, Object.id, true);
				}
				ruleGroupSelect.append($("<option />").val(Object.id).text(text));
			});
		}

	});

}


function modalButtonHandler(){
	$("#meButton").click(function() {
		$(this).button('loading');

	   	updateRuleGroup();			
	});
	
	$("#modalcancel").click(function() {			
					
	});
}


function showUpdateModal() {
    $("#manageModal").modal('show');
 	$("#meButton").button('reset'); 
	$('#meButton').prop('disabled', false);	   
}


function updateRuleGroup(){	

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

	console.log("Selected rules: " + requestBody + "\nmessage:" + messageBody);

	if (rule_count == 0) {
		$("#manageModal").modal('hide');
		$("#meButton").button('reset');
		$('#meButton').prop('disabled', false);

		$('#error_div').addClass("alert alert-danger");
		$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Error.</strong> No images are selected.');

		return;
	}

	var url = protocol + "/api/services/set_namespaces_to_group?openid=" + openid + "&group=" + selectedRuleGroup;	
	
	url = url + "&tenant=" + $("#tenantSelect").val();

	$.ajax({
		type : "PUT",
		url : url,
		data : requestBody,
		dataType : "text",
		aync : false,
		contentType : "application/text",
		success : function(data) {
			
			$("#manageModal").modal('hide');
			$("#meButton").button('reset');
			$('#meButton').prop('disabled', false);

			refresh();
			$('#error_div').addClass("alert alert-success");
			$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Success.</strong> You have changed ' + rule_count + " images to group " + selectedRuleGroup + "." );	
			rule_count = 0;

		},
		error : function(jqXHR, textStatus, errorThrown) {

			$("#manageModal").modal('hide');
			$("#meButton").button('reset');
			$('#meButton').prop('disabled', false);

			$('#error_div').addClass("alert alert-danger");
			$('#error_div').html('<a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a><strong>Error.</strong>' + textStatus);
		}
			
	});
			

}

