// The answers to an invitation (RSVP), as the event menu and the details view offer them.
// Not a .pragma library: i18nc comes from the importing component's context.

function choices() {
	return [
		{ status: 'accepted', icon: "dialog-ok-apply",
			text: i18nc("RSVP", "Yes"), seriesText: i18nc("RSVP", "Yes to All Events") },
		{ status: 'tentative', icon: "question",
			text: i18nc("RSVP", "Maybe"), seriesText: i18nc("RSVP", "Maybe to All Events") },
		{ status: 'declined', icon: "dialog-cancel",
			text: i18nc("RSVP", "No"), seriesText: i18nc("RSVP", "No to All Events") },
	]
}
