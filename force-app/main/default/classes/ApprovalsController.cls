/*
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* Controller class for Approvals Page. 
* ──────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Ashwin Bretto   <abretto@selastech.com>
* @modifiedBy     Vignesh   <vsadhasivam@selastech.com>
* @maintainedBy   Ashwin Bretto   <abretto@selastech.com>
* @version        1.0
* @created        2019-01-09
* @modified       2019-08-29
* ──────────────────────────────────────────────────────────────────────────────────────────────────
*/
public with sharing class ApprovalsController {
    
    public Id userId {get; set;}
    public Id recordId {get; set;}
    public String namespace;
    public List<ApprovalSet> approvalSets {get; set;}
    public Set<Id> queueIdSet = new Set<Id>();
    public static Set<Id> subordinatesOfCurrentUser;
    public String selectedRadio{get;set;}
    public ApprovalSet currentApproval {get; set;}
    public Integer currentApprovalIndex {get;set;}
    public Boolean reAssign {get; set;}
    
    public ApprovalsController() {
    
        this.userId = UserInfo.getUserId();
        namespace = 'nu_dse__';
        getsubordinatesOfCurrentUser();
        getUserMemberGroup();
        selectedRadio = 'nu_dse__Prospect__c';
        reAssign = false;
        this.currentApproval = new ApprovalSet();
    }
    
    public void getsubordinatesOfCurrentUser() {
        
        for (User subUser : [SELECT Id, Name, ProfileId, Profile.Name, ManagerId FROM User WHERE ManagerId = :this.userId]) {   
            subordinatesOfCurrentUser.add(subUser.Id); 
        }
    }
    
    public void getUserMemberGroup() {
        // Collect the groupIds which the current user added as member[SF-337]. 
        Set<Id> currentUserGroupIds = new Set<Id>();

        for(GroupMember grpMember : [SELECT GroupId, Group.Name FROM GroupMember 
                                        WHERE UserOrGroupId = :this.userId]){
            
            if (String.isNotBlank(grpMember.GroupId)) {            
                currentUserGroupIds.add(grpMember.GroupId);
            }
        }

        for(GroupMember grpMember : [SELECT GroupId, Group.Name FROM GroupMember 
                                     WHERE (UserOrGroupId = :this.userId OR UserOrGroupId IN :currentUserGroupIds)
                                        AND Group.Type = 'Queue']){
        
            if (String.isNotBlank(grpMember.GroupId)) {            
                queueIdSet.add(grpMember.GroupId);
            }
        }
    }
        
    public void onFilterChange() {
    
        String filterBy = ApexPages.currentPage().getParameters().get('filterBy');
        this.reAssign = false;

        if (filterBy == 'me') {
        
            List<ApprovalSet> assignedToMe = new List<ApprovalSet>();
            assignedToMe = (List<ApprovalSet>)JSON.deserialize(JSON.serialize(getAllApprovals()),List<ApprovalSet>.class);
            List<ApprovalSet> filteredApprovals = new List<ApprovalSet>();
            
            for (ApprovalSet appSet : assignedToMe) {
        
                if (appSet.approval != null && String.isNotBlank(appSet.approval.asignedTo) && 
                    String.isNotBlank(this.userId) && appSet.approval.asignedTo == this.userId) {
                    
                    filteredApprovals.add(appSet);
                }
            }
            this.approvalSets = filteredApprovals;
            
        } else if (filterBy == 'all') {
        
            this.approvalSets = new List<ApprovalSet>(getAllApprovals());
            
        } else if (filterBy == 'queue') {
            
            List<ApprovalSet> assignedToQueue = new List<ApprovalSet>();
            assignedToQueue = (List<ApprovalSet>)JSON.deserialize(JSON.serialize(getAllApprovals()),List<ApprovalSet>.class);
            List<ApprovalSet> filteredApprovals = new List<ApprovalSet>();
            
            for (ApprovalSet appSet : assignedToQueue) {
        
                if (String.isNotBlank(appSet.approval.asignedTo) && queueIdSet.isEmpty() == FALSE &&  
                    queueIdSet.contains(appSet.approval.asignedTo)) {
                        
                    filteredApprovals.add(appSet);
                }
            }
            this.approvalSets = filteredApprovals;
        }
    }
    
    public void setCurrentApproval() {

        this.currentApproval = this.approvalSets[this.currentApprovalIndex];
        this.reAssign = true;
    }

    public void reAssignApproval() {

        ProcessInstanceWorkItem updateWorkItem = new ProcessInstanceWorkItem();
        updateWorkItem.Id = this.currentApproval.workItemId;
        updateWorkItem.ActorId = UserInfo.getUserId();
        update updateWorkItem;
        this.reAssign = false;
        this.currentApproval = new ApprovalSet();
    }

    public void cancelReAssignApproval() {

        this.reAssign = false;
        this.currentApproval = new ApprovalSet();
    }

    public void renderApprovals() {
        
        getAllApprovals();
    }
    
    public List<ApprovalSet> getAllApprovals() {
        
        try {
            System.debug('selectedRadio :::: ' + selectedRadio);
            this.approvalSets = getApprovals(selectedRadio, this.userId, this.queueIdSet);
            
        } catch(Exception e) {
            
        }
        return approvalSets;
    }
    
    public static List<ApprovalSet> getApprovals(String selectedValue, Id userId, Set<Id> queueIdSet) {
        
        Map<String, ApprovalSet> processInstApprovalsMap = new Map<String, ApprovalSet>();
        Set<Id> targetObjectIdSet = new Set<Id>();
        // Reduced record limit to 500[SF-333]
        for(ProcessInstance procInstance : [SELECT Id, ProcessDefinitionId, ProcessDefinition.Name, TargetObjectId, 
                                                LastActorId, LastActor.Name, TargetObject.Name, CreatedDate, SubmittedById, SubmittedBy.Name,
                                            (SELECT Actor.Name, ElapsedTimeInHours, ElapsedTimeInMinutes 
                                                FROM Workitems ORDER By ElapsedTimeInMinutes DESC),
                                            (SELECT StepStatus, ElapsedTimeInMinutes, ElapsedTimeInHours FROM StepsAndWorkitems 
                                                WHERE StepStatus = 'Reassigned' ORDER By CreatedDate DESC LIMIT 1)
                                            FROM ProcessInstance 
                                            WHERE TargetObject.Type = :selectedValue
                                            AND Status = 'Pending'
                                            ORDER By CreatedDate ASC LIMIT 500]) {
            
            ApprovalRecord appRec = new ApprovalRecord(procInstance, userId);
            if(procInstance.Workitems != null && procInstance.Workitems.isEmpty() == FALSE) {
            
                if(procInstance.Workitems[0].ElapsedTimeInHours != null) {
                    appRec.elapsedHours = Integer.valueOf(procInstance.Workitems[0].ElapsedTimeInHours);
                }
                
                if (procInstance.Workitems[0].ElapsedTimeInMinutes != null && appRec.elapsedHours != null) {
                    appRec.elapsedMins = getMinutes(procInstance.Workitems[0].ElapsedTimeInMinutes , appRec.elapsedHours);
                    // Updated elapsedTotalMins for sorting Time in Queue[SF-339]
                    appRec.elapsedTotalMins = Integer.valueOf(procInstance.Workitems[0].ElapsedTimeInMinutes);
                }

                if(procInstance.StepsAndWorkitems != null && procInstance.StepsAndWorkitems.isEmpty() == FALSE) {
                
                    if(procInstance.Workitems[0].ElapsedTimeInHours != null
                        && procInstance.StepsAndWorkitems[0].ElapsedTimeInHours != null) {
                        appRec.reAssignedElapsedHours = Integer.valueOf(procInstance.Workitems[0].ElapsedTimeInHours - procInstance.StepsAndWorkitems[0].ElapsedTimeInHours);
                    }
                    if (procInstance.Workitems[0].ElapsedTimeInMinutes != null && appRec.elapsedHours != null
                        && procInstance.StepsAndWorkitems[0].ElapsedTimeInMinutes != null) {
                        appRec.reAssignedElapsedMins = getMinutes(procInstance.Workitems[0].ElapsedTimeInMinutes - procInstance.StepsAndWorkitems[0].ElapsedTimeInMinutes , appRec.reAssignedElapsedHours);
                        appRec.reAssignedElapsedTotalMins = Integer.valueOf(procInstance.Workitems[0].ElapsedTimeInMinutes - procInstance.StepsAndWorkitems[0].ElapsedTimeInMinutes);
                    }
                } else {
                   
                    appRec.reAssignedElapsedHours = 0;
                    appRec.reAssignedElapsedMins = 0;
                    appRec.reAssignedElapsedTotalMins = 0;
                }
                
            } else {
                
                appRec.elapsedHours = 0;
                appRec.elapsedMins = 0;
                appRec.elapsedTotalMins = 0;
                appRec.reAssignedElapsedHours = 0;
                appRec.reAssignedElapsedMins = 0;
                appRec.reAssignedElapsedTotalMins = 0;
            }

            String targetObjId_ProcDefId = '';
            
            if (String.isNotBlank(procInstance.TargetObjectId) && String.isNotBlank(procInstance.ProcessDefinitionId)) {
            
                targetObjId_ProcDefId = Id.valueOf(procInstance.TargetObjectId) + '_' + Id.valueOf(procInstance.ProcessDefinitionId);
            }
                        
            if (procInstance.Workitems != null && procInstance.Workitems.isEmpty() == FALSE && procInstance.Workitems[0] != null) {
            
                if (procInstance.Workitems[0].Actor != null) {
                
                    appRec.asignedTo = procInstance.Workitems[0].Actor.Id;
                    appRec.asignedToName = procInstance.Workitems[0].Actor.Name;
                }
                appRec.workItemId = procInstance.Workitems[0].Id;             
            }
            
            if (String.isNotBlank(appRec.asignedTo)) {
            
                if (appRec.asignedTo == userId) {                
                    appRec.showActions = TRUE;
                } else if (queueIdSet.contains(appRec.asignedTo)) {                
                    appRec.showActions = TRUE;
                } else if (subordinatesOfCurrentUser != null && subordinatesOfCurrentUser.isEmpty() == FALSE 
                            && String.isNotBlank(appRec.submittedBy) && subordinatesOfCurrentUser.contains(appRec.submittedBy)) {                
                    appRec.showActions = TRUE;
                }
            }
        
            if (String.isNotBlank(targetObjId_ProcDefId)) {
            
                appRec.submitStatus = 'Initial Submit';
                processInstApprovalsMap.put(targetObjId_ProcDefId, new ApprovalSet(appRec));
                targetObjectIdSet.add(procInstance.TargetObjectId);
            }
        }

        if(targetObjectIdSet.isEmpty() == false) {
            // Added LastActor.Name, LastActorId in query to show last rejected user name in approval[SF-62]. 
            Set<String> skipApprovedDefIds = new Set<String>(); 
            Set<String> skipRejectedDefIds = new Set<String>();

            for(ProcessInstance procInstance : [SELECT ProcessDefinitionId, TargetObjectId, LastActor.Name, LastActorId, Status
                                                FROM ProcessInstance 
                                                WHERE TargetObject.Type = :selectedValue
                                                    AND TargetObjectId IN :targetObjectIdSet
                                                    AND (Status = 'Rejected' OR Status = 'Approved')
                                                ORDER By CreatedDate DESC]){

                String targetObjId_ProcDefId = '';
                
                if (String.isNotBlank(procInstance.TargetObjectId) && String.isNotBlank(procInstance.ProcessDefinitionId)) {
                
                    targetObjId_ProcDefId = Id.valueOf(procInstance.TargetObjectId) + '_' + Id.valueOf(procInstance.ProcessDefinitionId);
                    if (processInstApprovalsMap.containsKey(targetObjId_ProcDefId)) {
                        
                        if((procInstance.Status == 'Rejected')
                            && skipRejectedDefIds.contains(targetObjId_ProcDefId) == false) {
                            
                            processInstApprovalsMap.get(targetObjId_ProcDefId).approval.submitStatus = 'Resubmit';
                            // Added rejectedBy, rejectedByName to show last rejected user name in approval[SF-62]. 
                            processInstApprovalsMap.get(targetObjId_ProcDefId).approval.lastRejectedBy = procInstance.LastActorId;
                            processInstApprovalsMap.get(targetObjId_ProcDefId).approval.lastRejectedByName = procInstance.LastActor.Name;
                            skipRejectedDefIds.add(targetObjId_ProcDefId);

                        } else if(procInstance.Status == 'Approved'
                                  && skipApprovedDefIds.contains(targetObjId_ProcDefId) == false) {

                            processInstApprovalsMap.get(targetObjId_ProcDefId).approval.submitStatus = 'Resubmit';
                            // Added ApprovedBy, ApprovedByName to show last rejected user name in approval[SF-333]. 
                            processInstApprovalsMap.get(targetObjId_ProcDefId).approval.lastApprovedBy = procInstance.LastActorId;
                            processInstApprovalsMap.get(targetObjId_ProcDefId).approval.lastApprovedByName = procInstance.LastActor.Name;
                            skipApprovedDefIds.add(targetObjId_ProcDefId);
                        }
                    } 
                }

            }
            // Added query to get target object records created date[SF-62]
            String queryStr = 'SELECT Id, CreatedDate FROM '+ selectedValue + ' WHERE Id IN :targetObjectIdSet';
            Map<Id, SObject> selectedObjectMap = new Map<Id, SObject>(Database.query(queryStr));
            // Assign page showing approval record target object createdDate[SF-62]
            for(String approvalId : processInstApprovalsMap.keySet()) {

                if(processInstApprovalsMap.get(approvalId).approval.targetId != null
                    && selectedObjectMap.containsKey(processInstApprovalsMap.get(approvalId).approval.targetId) == true) {
                    
                    DateTime createdDate  = DateTime.valueOf((selectedObjectMap.get(processInstApprovalsMap.get(approvalId).approval.targetId).get('CreatedDate')));
                    processInstApprovalsMap.get(approvalId).approval.CreatedDate = createdDate.format('MM-dd-YYYY');
                }
            }
        }
        return processInstApprovalsMap.values();
    }
    
    /* public static String toDateString(DateTime activityDate) {
        String dateFormat = 'MM/dd/yyyy';
        
        if(activityDate != null) {
        
            return activityDate.format(dateFormat);
        }
        return '';
    } */
    
    public static Integer getMinutes(Decimal totalElapsedMinutes, Integer elapsedHours) {
    
        return Integer.valueOf(totalElapsedMinutes - (60 * elapsedHours));
    }
    
    public static String getObjectLabel(Id recordId) {
        String objectLabel = '';
        
        if(recordId != null) {
        
            objectLabel = recordId.getSObjectType().getDescribe().getLabel();
        }
        return objectLabel;
    }
        
    public class ApprovalSet {
        
        public String approvalName {get; set;}
        public String objectTypeName {get; set;}
        public String tradelineid {get; set;}
        public String recordName {get; set;}
        public String recordId {get; set;}
        // Removed status column in Approvals table [SF-62]
        public Id workItemId {get; set;}
        public ApprovalRecord approval {get; set;}

        public ApprovalSet(){}
        
        public ApprovalSet(ApprovalRecord approval) {
            
            this.approvalName = approval.approvalName;
            this.objectTypeName = ApprovalsController.getObjectLabel(approval.targetId);
            this.recordName = approval.targetObjectName;
            this.recordId = approval.targetId;
            
            if(approval.approvalType == 'WORKITEM') {
                
                this.workItemId = approval.workItemId;
            }
            this.approval = approval;
        }
    }
    
    public class ApprovalRecord {
        
        public Id asignedTo {get; set;}
        public Id submittedBy {get; set;}
        public String asignedToName {get; set;}
        public String submittedByName {get; set;}
        public Integer elapsedHours {get; set;}
        public Integer elapsedMins {get; set;}
        // Added elapsedTotalMins for sorting Time in Queue[SF-339]
        public Integer elapsedTotalMins {get; set;}
        // Removed process status, completed date[SF-62]
        // Removed Object name
        public Id targetId {get; set;}
        public Id approvalId {get; set;}
        public String approvalName { get; set;}
        public String targetObjectName {get; set;}
        // Changed CompletedDate variable as TargetObject createdDate[SF-62]
        public String createdDate {get; set;}
        public Id workItemId {get; set;}
        public Id instanceId {get; set;}
        public String approvalType { get; set;}
        public String submitStatus { get; set;}
        public Boolean showActions {get; set;}
        // Added two variables to show last rejected user name in approval[SF-62]. 
        public String lastRejectedBy { get; set;}
        public String lastRejectedByName { get; set;}
        public String lastApprovedBy { get; set;}
        public String lastApprovedByName { get; set;}
        public Integer reAssignedElapsedHours {get; set;}
        public Integer reAssignedElapsedMins {get; set;}
        public Integer reAssignedElapsedTotalMins {get; set;}

        public ApprovalRecord(ProcessInstance processInstance, Id userId) {
            this.approvalType = 'WORKITEM';
            
            if(processInstance != null) {
            
                this.asignedTo = processInstance.LastActor.Id;
                this.asignedToName = processInstance.LastActor.Name;
                // Removed process status, CompletedDate[SF-62]
                // Removed object name 
                this.targetId = processInstance.TargetObjectId;
                // Removed CompletedDate value assignments[SF-62]
                this.approvalId = processInstance.ProcessDefinitionId;
                this.approvalName = processInstance.ProcessDefinition.Name;
                this.instanceId = processInstance.Id;
                this.submittedBy = processInstance.SubmittedById;
                this.submittedByName = processInstance.SubmittedBy.Name;
                
                if(processInstance.TargetObject.get('Name') != null) {
                
                    this.targetObjectName = (String) processInstance.TargetObject.get('Name');
                }
            }
        }        
    }    
}