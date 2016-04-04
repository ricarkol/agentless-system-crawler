
pathArray = window.location.href.split('/');
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;
var firstLoad= true;
var tableRef = null;

var images = {};
var compliance_status = "";
var selectedRuleGroup = "ITCS104";
var tenant = "TOYOTA"

$(document).ready(function(){
	buildTable();
	fillRuleGroupBox();
	getRules();
	
	//for (var id in images) {
		//console.log(images[id]);
	//}
});


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
		    "scrollY":        "450px",
		    "order": [[ 1, "asc" ]],
			"scrollCollapse": false,
			"oLanguage": {
					   "sEmptyTable":     "No records found",
					   "sLoadingRecords": "Loading...",
					   "sProcessing": "DataTables is currently busy"
					   },			

				   "dom": '<"row" <"col-lg-4"<"upper-left">><"col-lg-6 text-center"lf><"col-lg-2"<"upper-right text-right">>>t<"row"<"col-lg-3"<"text-left"i>><"col-lg-6 text-center"p><"col-lg-3"<"lower-right text-right">>>'
			
		});
	
			
	$("div.upper-left").html('<select class="form-control" id="ruleGroupSelect" onchange="setSelectedRuleGroup(this.id)"></select>');	

		$("div.upper-right").html('<button type="button" class="btn btn-default btn-md" onclick="refresh()"><i class="fa fa-refresh"></i></button>&nbsp;&nbsp;<button type="button" id="updateb1" onclick="showUpdateModal(this.id)" class="btn btn-default">Update</button>');
	   $("div.lower-right").html('<button type="button" id="updateb2" onclick="showUpdateModal(this.id)" class="btn btn-default btn-md">Update</button>');	
	
	

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
				// flag = 0
				//console.log("**** " + Object.name);
				
				data1 = data1+ '{"checkbox":'+ '"<input type=checkbox class=checkvm id =checkvmid value='+ Object.id + '> </input>"' +",";
				data1 = data1 + '"rule_name":' + '"' + Object.name + '"' + ",";
				data1 = data1 + '"section_name":' + '"' + Object.rule_group_name + '"' + ",";
				data1 = data1 + '"script_path":' + '"' + Object.script_path + '"' + ",";
				data1 = data1 + '"description":' + '"' + Object.description + '"' + ",";
				data1 = data1 + '"long_description":' + '"' + Object.long_description + '"' + "},";
				
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

	popupRules();

}


function getRules_kasa() {

	$.ajax({
		type : "GET",
		contentType : "application/json; charset=utf-8",
		url : 'https://kasa.sl.cloud9.ibm.com:9292/api/images',
		dataType : 'json',
		async : true,
		data : "{}",
		success : function(data) {
			$.each(data, function(idx, obj) {
				images[obj.id]='{"image_name":"' + obj.image_name + '","image_id":"' + obj.image_id + '"}';
			});
			showImageStatus();
		},
		error : function(xhr, status, error) {
			$("#divErrorMessages").empty().append(status);
			$("#divErrorMessages").append(xhr.responseText);

			alert(xhr.responseText);
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

	var url = protocol + "/api/get_tenant_rules?tenant=TOYOTA\&group=" + getSelectedRuleGroup();

	console.log(url);
	
	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : callShowResult,

	});    	

}


function popupRules() {


	var url = protocol + "/api/get_rule_descriptions";


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


function checkAllRules(checkall) {
	
	var checkvms = document.getElementsByTagName('input');
	for ( var i = 0; i < checkvms.length; i++) {
		if (checkvms[i].type == 'checkbox') {
			checkvms[i].checked = checkall.checked;
		}
	}
}


function fillRuleGroupBox() {	

	var url = protocol + "/api/get_rule_assign_groups?tenant=" + tenant;
	console.log("URL:" + url);
	
	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json",
		contentType : "application/json",
		success : function(data) {
			console.log(data);
			
			var ruleGroupSelect = $("#ruleGroupSelect").empty();
			ruleGroupSelect.append($("<option />").val("all").text("-- Select Rule Group --"));		

			$.each(data, function(object, Object) {				
					
					ruleGroupSelect.append($("<option />").val(Object.name).text(Object.name));
			});
		}

	});
}

function setSelectedRuleGroup(id)
{
	selectedRuleGroup = null;
	var ruleGroupSelect = document.getElementById(id);
	selectedRuleGroup = ruleGroupSelect.options[ruleGroupSelect.selectedIndex].value;	
	refresh();
	
	fillRuleGroupBoxForSelect(selectedRuleGroup);	
}


function fillRuleGroupBoxForSelect(cat) {	

	var url = protocol + "/api/get_rule_assign_groups?tenant=" + tenant;
	console.log("URL:" + url);
	
	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json",
		contentType : "application/json",
		success : function(data) {
			console.log(data);
			
			var ruleGroupSelect = $("#ruleGroupSelect").empty();
			ruleGroupSelect.append($("<option />").val("ITCS104").text("-- Select Rule Group --"));		

			$.each(data, function(object, Object) {				
					if(cat == Object.name ){
						ruleGroupSelect.append($("<option selected/>").val(Object.name).text(Object.name));
					}else{
						ruleGroupSelect.append($("<option />").val(Object.name).text(Object.name));

					}
					
			});
		}

	});
}


function getSelectedRuleGroup()
{
	return selectedRuleGroup;
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

	var ruleGroup = getSelectedRuleGroup();
	
	getRules();
	
	
	
}


function showUpdateModal() {
    $("#manageModal").modal('show');
  $("#meButton").button('reset'); 
	$('#meButton').prop('disabled', false);			

//updateRuleGroup("ITCS105");
 
    $("#meButton").click(function() {
		console.log("inside mbutton function");
		
		var btn = $(this);
	 
		//Change state of button to processing
		btn.button('loading');

		var ruleGroupName = document.getElementById("j_rule_group_name").value.trim();
	
	   	updateRuleGroup(ruleGroupName);			
		
	});
	
	$("#modalcancel").click(function() {			
					
	});
}

function updateRuleGroup(ruleGroupName){	

	console.log("inside update rule group");
	var rules = [];
	var rule_count = 0;
	var requestBody = "[";
	var url = protocol + "/api/set_tenant_rules?tenant=TOYOTA&group=" + ruleGroupName;	
	var RequestType = "POST";


	var rules = document.getElementsByClassName('checkvm');
	console.log("rules: " + rules);


	for (var i = 0; rules[i]; ++i) {
		if (rules[i].checked) {
			checkedValue = rules[i].value;

			if (rule_count ==  0) {	
				requestBody = requestBody + '"' + rules[i].value + '"';
			} else {
				requestBody = requestBody + ', "' + rules[i].value + '"';
			}
			rule_count++;
		}

	}
	requestBody = requestBody + ']';
	
	console.log("rule group name: " + ruleGroupName + " : " + requestBody);

	$.ajax({
		type : RequestType,
		url : url,
		data : requestBody,
		dataType : "text",
		aync : false,
		contentType : "application/text",
		success : function(data) {
			console.log(ruleGroupName + " update complete" + data);
			
			$("#manageModal").modal('hide');
			$("#meButton").button('reset');
			$('#meButton').prop('disabled', false);

			selectedRuleGroup = ruleGroupName;
			refresh();
			$('#error_div').addClass("alert alert-success");
			$('#error_div').html('<strong>Success.</strong> You have updated ' + rule_count + " rules to group " + ruleGroupName + "." );	
			rule_count = 0;

			fillRuleGroupBoxForSelect(ruleGroupName);
		},
		error : function(jqXHR, textStatus, errorThrown) {
			console.log(textStatus, errorThrown);
			$('#error_div').addClass("alert alert-danger");
			$('#error_div').html('<strong>Error.</strong>' + textStatus);
								}
			
									});
			

}

