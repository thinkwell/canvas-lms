define [
  'jquery',
  'i18n!calendar'
  'jst/calendar/appointmentGroupList'
  'jst/calendar/schedulerRightSideAdminSection'
  'compiled/calendar/EditAppointmentGroupDialog'
  'compiled/calendar/MessageParticipantsDialog'
  'jst/calendar/deleteItem'
  'jquery.instructure_date_and_time'
  'jquery.instructure_jquery_patches'
  'jquery.instructure_misc_plugins'
  'vendor/jquery.ba-tinypubsub'
  'vendor/jquery.spin'
], ($, I18n, appointmentGroupListTemplate, schedulerRightSideAdminSectionTemplate, EditAppointmentGroupDialog, MessageParticipantsDialog, deleteItemTemplate) ->

  class Scheduler
    constructor: (selector, @calendar) ->
      @div = $ selector
      @contexts = @calendar.contexts

      @listDiv = @div.find(".appointment-list")

      @div.delegate('.single_item_done_button', 'click', @doneClick)

      @div.delegate('.view_calendar_link', 'click', @viewCalendarLinkClick)
      @listDiv.delegate('.edit_link', 'click', @editLinkClick)
      @listDiv.delegate('.message_link', 'click', @messageLinkClick)
      @listDiv.delegate('.delete_link', 'click', @deleteLinkClick)
      @listDiv.delegate('.show_event_link', 'click', @showEventLinkClick)

      if @canManageAGroup()
        @div.addClass('can-manage')
        @rightSideAdminSection = $(schedulerRightSideAdminSectionTemplate())
        @rightSideAdminSection.find(".create_link").click @createClick

      $.subscribe "CommonEvent/eventSaved", @eventSaved
      $.subscribe "CommonEvent/eventDeleted", @eventDeleted

    createClick: (jsEvent) =>
      jsEvent.preventDefault()

      group = {
        contexts: @calendar.contexts
      }

      @createDialog = new EditAppointmentGroupDialog(group, @dialogCloseCB)
      @createDialog.show()

    dialogCloseCB: (saved) =>
      if saved
        @calendar.dataSource.clearCache()
        @loadData()

    eventSaved: (event) =>
      if @active
        @calendar.dataSource.clearCache()
        @loadData()

    eventDeleted: (event) =>
      if @active
        @calendar.dataSource.clearCache()
        @loadData()

    toggleListMode: (showListMode)->
      if showListMode
        delete @viewingGroup
        @calendar.updateFragment appointment_group_id: null
        @showList()
        if @canManageAGroup()
          $('#right-side .rs-section').hide()

          @rightSideAdminSection.appendTo('#right-side')
        else
          $('#right-side-wrapper').hide()
      else
        $('#right-side-wrapper').show()
        $('#right-side .rs-section').not("#undated-events, #calendar-feed").show()
        # we have to .detach() because of the css that puts lines under each .rs-section except the last,
        # if we just .hide() it would still be there so the :last-child selector would apply to it,
        # not the last _visible_ element
        @rightSideAdminSection?.detach()

    show: () =>
      $("#undated-events, #calendar-feed").hide()
      @active = true
      @div.show()
      @loadData()
      @toggleListMode(true)
      $.publish "Calendar/saveVisibleContextListAndClear"

    hide: () =>
      $("#undated-events, #calendar-feed").show()
      @active = false
      @div.hide()
      @toggleListMode(false)
      @calendar.displayAppointmentEvents = null
      $.publish "Calendar/restoreVisibleContextList"

    canManageAGroup: () =>
      for contextInfo in @contexts
        if contextInfo.can_create_appointment_groups
          return true
      false

    loadData: () =>
      if not @loadingDeferred || (@loadingDeferred && not @loadingDeferred.isResolved())
        @loadingDeferred = new $.Deferred()

      @groups = {}
      @loadingDiv ?= $('<div id="scheduler-loading" />').appendTo(@div).spin()

      @calendar.dataSource.getAppointmentGroups @canManageAGroup(), (data) =>
        for group in data
          @groups[group.id] = group
        @redraw()
        @loadingDeferred.resolve()

    redraw: () =>
      @loadingDiv.hide()

      if @groups
        groups = []
        for id, group of @groups
          # set an array of times that the student is signed up for
          group.signed_up_times = null
          if group.appointmentEvents
            for appointmentEvent in group.appointmentEvents when appointmentEvent.object.reserved
              for childEvent in appointmentEvent.childEvents when childEvent.object.own_reservation
                group.signed_up_times ?= []
                group.signed_up_times.push
                  id: childEvent.id
                  formatted_time: childEvent.displayTimeString()

          # count how many people have signed up
          group.signed_up = 0
          if group.appointmentEvents
            for appointmentEvent in group.appointmentEvents
              group.signed_up += appointmentEvent.childEvents.length if appointmentEvent.childEvents

          # look up the context name for the group
          for contextInfo in @contexts when contextInfo.asset_string == group.context_code
            group.context = contextInfo

          group.published = group.workflow_state == "active"

          groups.push group

        html = appointmentGroupListTemplate
          appointment_groups: groups
          canManageAGroup: @canManageAGroup()
        @listDiv.find(".list-wrapper").html html

        if @viewingGroup
          @viewingGroup = @groups[@viewingGroup.id]
          if @viewingGroup
            @listDiv.find(".appointment-group-item[data-appointment-group-id='#{@viewingGroup.id}']").addClass('active')
            @calendar.displayAppointmentEvents = @viewingGroup
          else
            @toggleListMode(true)

      $.publish "Calendar/refetchEvents"

    viewCalendarLinkClick: (jsEvent) =>
      jsEvent.preventDefault()
      @viewCalendarForElement $(jsEvent.target)

    showEventLinkClick: (jsEvent) =>
      jsEvent.preventDefault()
      group = @viewCalendarForElement $(jsEvent.target)

      eventId = $(jsEvent.target).data('event-id')
      if eventId
        for appointmentEvent in group.object.appointmentEvents
          for childEvent in appointmentEvent.object.childEvents when childEvent.id == eventId
            @calendar.gotoDate(childEvent.start)
            return

    viewCalendarForElement: (el) =>
      thisItem = el.closest(".appointment-group-item")
      groupId = thisItem.data('appointment-group-id')
      thisItem.addClass('active')
      group = @groups?[groupId]
      @viewCalendarForGroup(@groups?[groupId])
      group

    viewCalendarForGroupId: (id) =>
      @loadData()
      @loadingDeferred.done =>
        @viewCalendarForGroup @groups?[id]

    viewCalendarForGroup: (group) =>
      @calendar.updateFragment appointment_group_id: group.id
      @toggleListMode(false)
      @viewingGroup = group

      @loadingDeferred.done =>
        @div.addClass('showing-single')

        @calendar.calendar.show()
        @calendar.calendar.fullCalendar('changeView', 'agendaWeek')

        if @viewingGroup.start_at
          @calendar.gotoDate($.parseFromISO(@viewingGroup.start_at).time)
        else
          @calendar.gotoDate(new Date())

        @calendar.displayAppointmentEvents = @viewingGroup
        $.publish "Calendar/refetchEvents"

    doneClick: (jsEvent) =>
      jsEvent.preventDefault()
      @toggleListMode(true)

    showList: () =>
      @div.removeClass('showing-single')
      @listDiv.find('.appointment-group-item').removeClass('active')

      @calendar.calendar.hide()
      @calendar.displayAppointmentEvents = null

    editLinkClick: (jsEvent) =>
      jsEvent.preventDefault()
      group = @groups?[$(jsEvent.target).closest(".appointment-group-item").data('appointment-group-id')]
      return unless group

      group.contexts = @calendar.contexts
      @createDialog = new EditAppointmentGroupDialog(group, @dialogCloseCB)
      @createDialog.show()

    deleteLinkClick: (jsEvent) =>
      jsEvent.preventDefault()
      group = @groups?[$(jsEvent.target).closest(".appointment-group-item").data('appointment-group-id')]
      return unless group

      $("<div />").confirmDelete
        url: group.url
        message: $ deleteItemTemplate(message: I18n.t('confirm_appointment_group_deletion', "Are you sure you want to delete this appointment group?"), details: I18n.t('appointment_group_deletion_details', "Deleting it will also delete any appointments that have been signed up for by students."))
        dialog: {title: I18n.t('confirm_deletion', "Confirm Deletion")}
        prepareData: ($dialog) => {cancel_reason: $dialog.find('#cancel_reason').val() }
        confirmed: () =>
          $(jsEvent.target).closest(".appointment-group-item").addClass("event_pending")
        success: () =>
          @calendar.dataSource.clearCache()
          @loadData()

    messageLinkClick: (jsEvent) =>
      jsEvent.preventDefault()
      group = @groups?[$(jsEvent.target).closest(".appointment-group-item").data('appointment-group-id')]
      @messageDialog = new MessageParticipantsDialog(group, @calendar.dataSource)
      @messageDialog.show()
