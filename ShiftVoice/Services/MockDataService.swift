import Foundation

enum MockDataService {
    static let currentUserId = "user_001"
    static let currentUserName = "Marcus Rivera"
    static let currentUserInitials = "MR"

    static let organization = Organization(
        id: "org_001",
        name: "Rivera Hospitality Group",
        ownerId: currentUserId,
        plan: .professional,
        industryType: .restaurant
    )

    static let locations: [Location] = [
        Location(id: "loc_001", name: "The Ember Room", address: "234 W 4th St, New York, NY", managerIds: ["user_001", "user_002", "user_003", "user_004"]),
        Location(id: "loc_002", name: "Saltwater Kitchen", address: "89 Ocean Ave, Brooklyn, NY", managerIds: ["user_001", "user_005", "user_006"]),
        Location(id: "loc_003", name: "Rooftop Social", address: "1200 Broadway, New York, NY", managerIds: ["user_001", "user_007"])
    ]

    static let teamMembers: [TeamMember] = [
        TeamMember(id: "user_001", name: "Marcus Rivera", email: "marcus@riverahg.com", role: .owner, roleTemplateId: "role_owner", locationIds: ["loc_001", "loc_002", "loc_003"]),
        TeamMember(id: "user_002", name: "Sarah Chen", email: "sarah@riverahg.com", role: .generalManager, roleTemplateId: "role_gm", locationIds: ["loc_001"]),
        TeamMember(id: "user_003", name: "Devon Williams", email: "devon@riverahg.com", role: .manager, roleTemplateId: "role_mgr", locationIds: ["loc_001"]),
        TeamMember(id: "user_004", name: "Ava Torres", email: "ava@riverahg.com", role: .shiftLead, roleTemplateId: "role_lead", locationIds: ["loc_001"]),
        TeamMember(id: "user_005", name: "James Park", email: "james@riverahg.com", role: .generalManager, roleTemplateId: "role_gm", locationIds: ["loc_002"]),
        TeamMember(id: "user_006", name: "Nia Johnson", email: "nia@riverahg.com", role: .manager, roleTemplateId: "role_mgr", locationIds: ["loc_002"]),
        TeamMember(id: "user_007", name: "Carlos Mendez", email: "carlos@riverahg.com", role: .manager, roleTemplateId: "role_mgr", locationIds: ["loc_003"])
    ]

    static func generateShiftNotes() -> [ShiftNote] {
        let now = Date()
        let cal = Calendar.current

        return [
            ShiftNote(
                id: "note_001",
                authorId: "user_003",
                authorName: "Devon Williams",
                authorInitials: "DW",
                locationId: "loc_001",
                shiftType: .closing,
                shiftTemplateId: "shift_close",
                rawTranscript: "Alright closing notes for tonight. We 86'd the salmon around 8pm, supplier shorted us again. Walk-in compressor is making that noise again, third time this week. Had a comp on table 14, guest found hair in their pasta, comped the whole table's entrees. Big night though, 247 covers. Also the POS terminal at station 3 is frozen again, needs a full restart. Oh and heads up, we have a 20-top VIP coming in tomorrow at 7, it's the Brennan anniversary party, they want the private dining room set with candles and the special menu.",
                audioDuration: 47,
                summary: "Busy closing with 247 covers. Salmon 86'd due to supplier shortage. Walk-in compressor issue recurring (3rd time this week). Comped table 14 for hair in pasta. POS station 3 frozen. VIP 20-top Brennan party tomorrow at 7pm needs private room setup.",
                categorizedItems: [
                    CategorizedItem(category: .eightySixed, categoryTemplateId: "cat_86", content: "Salmon — supplier shorted delivery, 86'd at 8pm", urgency: .nextShift),
                    CategorizedItem(category: .equipment, categoryTemplateId: "cat_equip", content: "Walk-in compressor making noise again — 3rd time this week", urgency: .immediate),
                    CategorizedItem(category: .equipment, categoryTemplateId: "cat_equip", content: "POS terminal station 3 frozen, needs full restart", urgency: .nextShift),
                    CategorizedItem(category: .guestIssue, categoryTemplateId: "cat_guest", content: "Table 14 — hair in pasta, comped all entrees", urgency: .fyi),
                    CategorizedItem(category: .reservation, categoryTemplateId: "cat_reso", content: "Brennan anniversary party — 20-top VIP, tomorrow 7pm, private dining room, candles + special menu", urgency: .immediate)
                ],
                actionItems: [
                    ActionItem(task: "Call seafood supplier re: salmon shortage", category: .eightySixed, categoryTemplateId: "cat_86", urgency: .nextShift, assignee: "Sarah Chen"),
                    ActionItem(task: "Schedule walk-in compressor repair — recurring issue", category: .equipment, categoryTemplateId: "cat_equip", urgency: .immediate),
                    ActionItem(task: "Restart POS terminal station 3", category: .equipment, categoryTemplateId: "cat_equip", urgency: .nextShift),
                    ActionItem(task: "Set up private dining room for Brennan party — candles, special menu", category: .reservation, categoryTemplateId: "cat_reso", urgency: .immediate)
                ],
                acknowledgments: [
                    Acknowledgment(userId: "user_002", userName: "Sarah Chen", timestamp: cal.date(byAdding: .hour, value: -1, to: now)!)
                ],
                createdAt: cal.date(byAdding: .hour, value: -3, to: now)!
            ),

            ShiftNote(
                id: "note_002",
                authorId: "user_002",
                authorName: "Sarah Chen",
                authorInitials: "SC",
                locationId: "loc_001",
                shiftType: .mid,
                shiftTemplateId: "shift_mid",
                rawTranscript: "Mid shift update. Lunch was solid, 89 covers. The new server Kayla is doing great, really picking up the floor fast. FYI the ice machine is leaking again by the service station, put a bucket under it for now. Health inspector is scheduled for next Tuesday, need to make sure all temp logs are current. Also restocked the bar with the wine delivery that came in.",
                audioDuration: 32,
                summary: "Solid lunch with 89 covers. New server Kayla performing well. Ice machine leaking at service station (bucket placed). Health inspector coming Tuesday — ensure temp logs current. Wine delivery restocked at bar.",
                categorizedItems: [
                    CategorizedItem(category: .staffNote, categoryTemplateId: "cat_staff", content: "New server Kayla doing great, picking up the floor quickly", urgency: .fyi),
                    CategorizedItem(category: .maintenance, categoryTemplateId: "cat_maint", content: "Ice machine leaking at service station — bucket placed temporarily", urgency: .thisWeek),
                    CategorizedItem(category: .healthSafety, categoryTemplateId: "cat_hs", content: "Health inspector scheduled next Tuesday — temp logs must be current", urgency: .thisWeek),
                    CategorizedItem(category: .inventory, categoryTemplateId: "cat_inv", content: "Wine delivery received and restocked at bar", urgency: .fyi)
                ],
                actionItems: [
                    ActionItem(task: "Fix ice machine leak at service station", category: .maintenance, categoryTemplateId: "cat_maint", urgency: .thisWeek),
                    ActionItem(task: "Verify all temperature logs are current before Tuesday inspection", category: .healthSafety, categoryTemplateId: "cat_hs", urgency: .thisWeek, status: .inProgress, assignee: "Devon Williams")
                ],
                acknowledgments: [
                    Acknowledgment(userId: "user_003", userName: "Devon Williams", timestamp: cal.date(byAdding: .hour, value: -5, to: now)!),
                    Acknowledgment(userId: "user_004", userName: "Ava Torres", timestamp: cal.date(byAdding: .hour, value: -4, to: now)!)
                ],
                createdAt: cal.date(byAdding: .hour, value: -8, to: now)!
            ),

            ShiftNote(
                id: "note_003",
                authorId: "user_004",
                authorName: "Ava Torres",
                authorInitials: "AT",
                locationId: "loc_001",
                shiftType: .opening,
                shiftTemplateId: "shift_open",
                rawTranscript: "Opening notes. Everything looks good from last night's close, Devon did a great job. Fryer oil in station 2 needs to be changed, it's getting dark. We're low on to-go containers, the medium ones. Produce delivery came in fine, everything looks fresh. Reminder that the Brennan party is tonight so we need all hands on deck.",
                audioDuration: 28,
                summary: "Clean open after last night. Fryer oil station 2 needs changing. Low on medium to-go containers. Produce delivery received in good condition. Brennan VIP party tonight — all hands needed.",
                categorizedItems: [
                    CategorizedItem(category: .equipment, categoryTemplateId: "cat_equip", content: "Fryer oil station 2 getting dark — needs changing", urgency: .nextShift),
                    CategorizedItem(category: .inventory, categoryTemplateId: "cat_inv", content: "Low on medium to-go containers", urgency: .thisWeek),
                    CategorizedItem(category: .general, categoryTemplateId: "cat_gen", content: "Produce delivery received, all fresh", urgency: .fyi),
                    CategorizedItem(category: .reservation, categoryTemplateId: "cat_reso", content: "Brennan VIP party tonight — all hands on deck", urgency: .immediate)
                ],
                actionItems: [
                    ActionItem(task: "Change fryer oil at station 2", category: .equipment, categoryTemplateId: "cat_equip", urgency: .nextShift),
                    ActionItem(task: "Order medium to-go containers", category: .inventory, categoryTemplateId: "cat_inv", urgency: .thisWeek)
                ],
                createdAt: cal.date(byAdding: .hour, value: -14, to: now)!
            ),

            ShiftNote(
                id: "note_004",
                authorId: "user_005",
                authorName: "James Park",
                authorInitials: "JP",
                locationId: "loc_002",
                shiftType: .closing,
                shiftTemplateId: "shift_close",
                rawTranscript: "Closing at Saltwater. Wild night, 198 covers for a Wednesday. We ran out of the lobster bisque by 7:30, had to 86 it. Two comps tonight, table 6 had an undercooked steak they sent back twice, comped their meals. Table 22 had a birthday and we forgot to bring out the dessert, comped a bottle of champagne. Dishwasher is running slow, might need the drain cleaned. Also the back door lock is sticking again.",
                audioDuration: 41,
                summary: "Busy Wednesday closing with 198 covers. Lobster bisque 86'd at 7:30. Two comps: table 6 (undercooked steak sent back twice), table 22 (missed birthday dessert, comped champagne). Dishwasher running slow — drain may need cleaning. Back door lock sticking.",
                categorizedItems: [
                    CategorizedItem(category: .eightySixed, categoryTemplateId: "cat_86", content: "Lobster bisque ran out by 7:30pm", urgency: .nextShift),
                    CategorizedItem(category: .guestIssue, categoryTemplateId: "cat_guest", content: "Table 6 — undercooked steak sent back twice, comped meals", urgency: .fyi),
                    CategorizedItem(category: .guestIssue, categoryTemplateId: "cat_guest", content: "Table 22 — forgot birthday dessert, comped champagne bottle", urgency: .fyi),
                    CategorizedItem(category: .equipment, categoryTemplateId: "cat_equip", content: "Dishwasher running slow — drain may need cleaning", urgency: .thisWeek),
                    CategorizedItem(category: .maintenance, categoryTemplateId: "cat_maint", content: "Back door lock sticking again", urgency: .thisWeek)
                ],
                actionItems: [
                    ActionItem(task: "Prep extra lobster bisque for tomorrow", category: .eightySixed, categoryTemplateId: "cat_86", urgency: .nextShift),
                    ActionItem(task: "Clean dishwasher drain", category: .equipment, categoryTemplateId: "cat_equip", urgency: .thisWeek),
                    ActionItem(task: "Fix back door lock", category: .maintenance, categoryTemplateId: "cat_maint", urgency: .thisWeek)
                ],
                acknowledgments: [],
                createdAt: cal.date(byAdding: .hour, value: -2, to: now)!
            ),

            ShiftNote(
                id: "note_005",
                authorId: "user_007",
                authorName: "Carlos Mendez",
                authorInitials: "CM",
                locationId: "loc_003",
                shiftType: .closing,
                shiftTemplateId: "shift_close",
                rawTranscript: "Rooftop closing notes. Slow night due to rain, only 67 covers. Outdoor heaters on the east side are out, two of them won't ignite. Beer delivery was short, missing the IPA kegs. Had to cut Happy Hour early because we ran out of the well tequila. No major issues otherwise, clean close.",
                audioDuration: 25,
                summary: "Slow rainy night with 67 covers. Two east-side outdoor heaters won't ignite. Beer delivery short — missing IPA kegs. Had to cut Happy Hour early (out of well tequila). Otherwise clean close.",
                categorizedItems: [
                    CategorizedItem(category: .equipment, categoryTemplateId: "cat_equip", content: "Two outdoor heaters (east side) won't ignite", urgency: .nextShift),
                    CategorizedItem(category: .inventory, categoryTemplateId: "cat_inv", content: "Beer delivery short — missing IPA kegs", urgency: .nextShift),
                    CategorizedItem(category: .eightySixed, categoryTemplateId: "cat_86", content: "Well tequila ran out, cut Happy Hour early", urgency: .nextShift)
                ],
                actionItems: [
                    ActionItem(task: "Service east-side outdoor heaters", category: .equipment, categoryTemplateId: "cat_equip", urgency: .nextShift),
                    ActionItem(task: "Follow up with beer distributor re: missing IPA kegs", category: .inventory, categoryTemplateId: "cat_inv", urgency: .nextShift),
                    ActionItem(task: "Restock well tequila", category: .inventory, categoryTemplateId: "cat_inv", urgency: .nextShift)
                ],
                acknowledgments: [],
                createdAt: cal.date(byAdding: .hour, value: -1, to: now)!
            )
        ]
    }

    static let recurringIssues: [RecurringIssue] = {
        let now = Date()
        let cal = Calendar.current
        return [
            RecurringIssue(
                description: "Walk-in compressor making noise",
                category: .equipment,
                categoryTemplateId: "cat_equip",
                locationId: "loc_001",
                locationName: "The Ember Room",
                mentionCount: 4,
                relatedNoteIds: ["note_001"],
                firstMentioned: cal.date(byAdding: .day, value: -12, to: now)!,
                lastMentioned: now
            ),
            RecurringIssue(
                description: "Ice machine leaking at service station",
                category: .maintenance,
                categoryTemplateId: "cat_maint",
                locationId: "loc_001",
                locationName: "The Ember Room",
                mentionCount: 3,
                relatedNoteIds: ["note_002"],
                firstMentioned: cal.date(byAdding: .day, value: -9, to: now)!,
                lastMentioned: cal.date(byAdding: .hour, value: -8, to: now)!
            ),
            RecurringIssue(
                description: "Back door lock sticking",
                category: .maintenance,
                categoryTemplateId: "cat_maint",
                locationId: "loc_002",
                locationName: "Saltwater Kitchen",
                mentionCount: 3,
                relatedNoteIds: ["note_004"],
                firstMentioned: cal.date(byAdding: .day, value: -14, to: now)!,
                lastMentioned: cal.date(byAdding: .hour, value: -2, to: now)!
            )
        ]
    }()
}
