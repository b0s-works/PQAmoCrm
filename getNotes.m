let
getFn = (limits as text, url as text, authQuery as record) =>
    let


/*
-------------------------------------
-------------Справочники-------------
-------------------------------------
*/
        //Запрос
authWebContents = Web.Contents(
            url,
                [
                    RelativePath="/private/api/auth.php",
                    Query=authQuery
                ]),
guideConnect = (url as text, authQuery as record) =>
    let
    getAccountInfo = Json.Document(Web.Contents(
        url,
        [
            RelativePath="/private/api/v2/json/accounts/current",
            Query=authQuery
        ])),
    getResponse = getAccountInfo[response],
    getResponse2 = getResponse[account]
in
    getResponse2,
        getAccountInfo = guideConnect(url, authQuery),

        //Имен пользователей
        usersRecord = getAccountInfo[users],
        usersToTable = Table.FromList(usersRecord, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        usersExpandNames = Table.ExpandRecordColumn(usersToTable, "Column1", {"id", "name"}, {"id", "name"}),
        usersExpandNamesToText = Table.TransformColumnTypes(usersExpandNames,{{"id", type text}}),

       //Названий статусов
        statusesRecord = getAccountInfo[leads_statuses],
        statusesToTable = Table.FromList(statusesRecord, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        statusesExpandNames = Table.ExpandRecordColumn(statusesToTable, "Column1", {"id", "name"}, {"id", "name"}),
        statusesChangeType = Table.TransformColumnTypes(statusesExpandNames,{{"id", type text}}),

        //пайплайны
        pipelinesRecord = getAccountInfo[pipelines],
        pipelinesToTable = Record.ToTable(pipelinesRecord),
        pipelinesCheckEmpty = Table.First(pipelinesToTable),
        pipelinesDelAnother = Table.SelectColumns(pipelinesToTable,{"Value"}),
        pipelinesExpandNames = Table.ExpandRecordColumn(pipelinesDelAnother, "Value", {"id", "name"}, {"id", "name"}),
        pipelinesChangeType = Table.TransformColumnTypes(pipelinesExpandNames,{{"id", type text}}),

        //Названий групп
        groupsRecord = getAccountInfo[groups],
        groupsToTable = Table.FromList(groupsRecord, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        groupsCheckEmpty = Table.First(groupsToTable),
        groupsExpandNames = Table.ExpandRecordColumn(groupsToTable, "Column1", {"id", "name"}, {"id", "name"}),
        groupsChangeType = Table.TransformColumnTypes(groupsExpandNames,{{"id", type text}}),

        //Типов задач
        notetypesRecord = getAccountInfo[note_types],
        notetypesToTable = Table.FromList(notetypesRecord, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        notetypesExpandNames = Table.ExpandRecordColumn(notetypesToTable, "Column1", {"id", "name", "code"}, {"id", "name", "code"}),
        notetypesCheckDefault = Table.AddColumn(notetypesExpandNames, "Пользовательская", each
            if [name] = "" then [code] else [name]),
        notetypesDelAnother = Table.SelectColumns(notetypesCheckDefault,{"id", "Пользовательская"}),
        notetypesRename = Table.RenameColumns(notetypesDelAnother,{{"Пользовательская", "name"}}),
        notetypesToText = Table.TransformColumnTypes(notetypesRename,{{"id", type text}}),

/*
-------------------------------------
-------------Справочники-------------
-------------------------------------
*/


        newAuthQuery = Record.Combine({
            authQuery,
            [limit_rows ="500"],
            [limit_offset=limits],
            [type="lead"]}),

        getQuery  = Json.Document(Web.Contents(url,
            [
                RelativePath="/private/api/v2/json/notes/list",
                Query=newAuthQuery
            ])),
        toTable = Record.ToTable(getQuery),
        delOther = Table.SelectColumns(toTable,{"Value"}),
        expand = Table.ExpandRecordColumn(delOther, "Value", {"notes"}, {"notes"}),
        expand1 = Table.ExpandListColumn(expand, "notes"),
        expand2 = Table.ExpandRecordColumn(expand1, "notes", {"id", "element_id", "element_type", "note_type", "date_create", "created_user_id", "last_modified", "text", "responsible_user_id", "account_id", "ATTACHEMENT", "group_id", "editable"}, {"id", "element_id", "element_type", "note_type", "date_create", "created_user_id", "last_modified", "text", "responsible_user_id", "account_id", "ATTACHEMENT", "group_id", "editable"}),


        //Перевод дат из timestamp
        timestampDateCreate = Table.AddColumn(expand2, "Date_create", each if [date_create] = 0 then null else #datetime(1970,1,1,0,0,0)+#duration(0,0,0,[date_create])),
        timestampDateModified = Table.AddColumn(timestampDateCreate, "Last_modified", each if [last_modified] = 0 then null else #datetime(1970,1,1,0,0,0)+#duration(0,0,0,[last_modified])),
        removeOldDates = Table.RemoveColumns(timestampDateModified,{"date_create", "last_modified"}),
        removeOldDatesToText = Table.TransformColumnTypes(removeOldDates,{{"created_user_id", type text}, {"responsible_user_id", type text}, {"element_type", type text}, {"note_type", type text}, {"group_id", type text}}),


        //merge со справочниками
        mergeWithCreateUserName = Table.NestedJoin(
            removeOldDatesToText,{"created_user_id"},
            usersExpandNamesToText,{"id"},
            "CreatedUser",JoinKind.LeftOuter),
        mergeWithResponsibleUserName = Table.NestedJoin(
            mergeWithCreateUserName,{"responsible_user_id"},
            usersExpandNamesToText,{"id"},
            "ResponsibleUser",JoinKind.LeftOuter),
        mergeWithGroupsName = if groupsCheckEmpty = null
            then mergeWithResponsibleUserName
            else Table.NestedJoin(
                mergeWithResponsibleUserName,{"group_id"},
                groupsChangeType,{"id"},
                "GroupName",JoinKind.LeftOuter),
        mergeWithNotetype = Table.NestedJoin(
            mergeWithGroupsName,{"note_type"},
            notetypesToText,{"id"},
            "NoteType",JoinKind.LeftOuter),

        //expand
        expandCreaterName = Table.ExpandTableColumn(mergeWithNotetype, "CreatedUser", {"name"}, {"CreatedUser.name"}),
        expandResponsibleName = Table.ExpandTableColumn(expandCreaterName, "ResponsibleUser", {"name"}, {"ResponsibleUser.name"}),
        expandGroupsName = if groupsCheckEmpty = null
            then expandResponsibleName
            else Table.ExpandTableColumn(expandResponsibleName, "GroupName", {"name"}, {"GroupName.name"}),
            
        addColumnTypeOfElement = Table.AddColumn(expandGroupsName, "Тип элемента", each
            if [element_type] = "2" then "Сделка" else
            if [element_type] = "1" then "Контакт" else
            if [element_type] = "3" then "Компания" else
            if [element_type] = "12" then "Покупатель" else "Неизвестно" ),


        expandNoteType = Table.ExpandTableColumn(addColumnTypeOfElement, "NoteType", {"name"}, {"NoteType.name"}),
    шаг1 = Table.RemoveColumns(expandNoteType,{"created_user_id", "responsible_user_id", "group_id", "note_type", "element_type"}), /*#"Разделить столбец по разделителю"*/

    шаг2 = Table.RenameColumns(шаг1, {"text", "textOriginal"}), /*Переименование колонки, что бы не было конфликта с будущей колонкой Text*/
    шаг3 = Table.DuplicateColumn(шаг2, "textOriginal", "textJSON"),  /*Дубликация колонки в колнку textJSON которая позже будет использована для обработки JSON в ней*/
    шаг4 = Table.TransformColumns(шаг3, {{"textJSON",  each if Text.Contains(_, "{""") then Json.Document(_) else null }}), /*#"Если textJSON содержит JSON тогда обработать JSON и записать результат в неё"*/
    шаг5 = Table.ExpandRecordColumn(шаг4, "textJSON", {"STATUS_NEW", "STATUS_OLD", "TEXT", "PIPELINE_ID_OLD", "PIPELINE_ID_NEW", "LOSS_REASON_ID", "HTML"}, {"STATUS_NEW", "STATUS_OLD", "TEXTFROMJSON", "PIPELINE_ID_OLD", "PIPELINE_ID_NEW", "LOSS_REASON_ID", "HTML"}), /*#"Извлечь из JSON записей поля и добавить их как колонки"*/
    //шаг6 = Table.AddColumn(шаг5, "Text", each if [NoteType.name] = "DEAL_STATUS_CHANGED" then [TEXTFROMJSON] else if Text.Contains([textOriginal], "{""") then if [HTML] <> null then Table.First(Html.Table([HTML], {{"link", "a[href^=""http""]", each [Attributes][href]}}), "link")[link] else if [TEXT] <> null then [TEXT] else [textOriginal] else [textOriginal]),
    //шаг6 = Table.AddColumn(шаг5, "Text", each if [NoteType.name] = "DEAL_STATUS_CHANGED" then [TEXTFROMJSON] else if Text.Contains([textOriginal], "{""") then if [HTML] <> null then [HTML] else if [TEXT] <> null then [TEXT] else [textOriginal] else [textOriginal]),
    шаг6 = Table.AddColumn(шаг5, "Text", each if [NoteType.name] = "DEAL_STATUS_CHANGED" then [TEXTFROMJSON] else if Text.Contains([textOriginal], "{""") then if [TEXTFROMJSON] <> null then [TEXTFROMJSON] else [textOriginal] else [textOriginal]),
    
    /*Изменениее типа колонок на тестовый, необходимое, для удачного сравнения полей в последующем вызове Table.NestedJoin*/
    шаг7  = Table.TransformColumnTypes(шаг6,{{"STATUS_NEW", type text}}),
    шаг8  = Table.TransformColumnTypes(шаг7,{{"STATUS_OLD", type text}}),
    шаг9  = Table.TransformColumnTypes(шаг8,{{"PIPELINE_ID_NEW", type text}}),
    шаг10  = Table.TransformColumnTypes(шаг9,{{"PIPELINE_ID_OLD", type text}}),


    mergeWithStatusNew = Table.NestedJoin(шаг10,{"STATUS_NEW"}, statusesChangeType,{"id"}, "NewStatus",JoinKind.LeftOuter),
    mergeWithStatusOld = Table.NestedJoin(mergeWithStatusNew,{"STATUS_OLD"}, statusesChangeType,{"id"}, "OldStatus",JoinKind.LeftOuter),
    mergeWithOldPipeline = Table.NestedJoin(mergeWithStatusOld,{"PIPELINE_ID_OLD"}, pipelinesChangeType,{"id"}, "OldPipeline",JoinKind.LeftOuter), 
    mergeWithNewPipeline = Table.NestedJoin(mergeWithOldPipeline,{"PIPELINE_ID_NEW"}, pipelinesChangeType,{"id"}, "NewPipeline",JoinKind.LeftOuter),

    #"Развернутый элемент NewStatus" = Table.ExpandTableColumn(mergeWithNewPipeline, "NewStatus", {"name"}, {"NewStatus.name"}),
    #"Развернутый элемент OldStatus" = Table.ExpandTableColumn(#"Развернутый элемент NewStatus", "OldStatus", {"name"}, {"OldStatus.name"}),
    #"Развернутый элемент OldPipeline" = Table.ExpandTableColumn(#"Развернутый элемент OldStatus", "OldPipeline", {"name"}, {"OldPipeline.name"}),
    #"Развернутый элемент NewPipeline" = Table.ExpandTableColumn(#"Развернутый элемент OldPipeline", "NewPipeline", {"name"}, {"NewPipeline.name"}),
    finaldel2 = Table.RemoveColumns(#"Развернутый элемент NewPipeline",{"STATUS_NEW", "STATUS_OLD", "PIPELINE_ID_OLD", "PIPELINE_ID_NEW", "textOriginal", "HTML", "TEXTFROMJSON"})
in
    finaldel2
in
getFn
