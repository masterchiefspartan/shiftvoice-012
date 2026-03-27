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

        func hoursAgo(_ hours: Int) -> Date {
            cal.date(byAdding: .hour, value: -hours, to: now)!
        }

        return [
            ShiftNote(
                id: "note_001",
                authorId: "user_003", authorName: "Devon Williams", authorInitials: "DW",
                locationId: "loc_001", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Alright closing notes for tonight. We 86'd the salmon around 8pm, supplier shorted us again. Walk-in compressor is making that noise again, third time this week. Had a comp on table 14, guest found hair in their pasta, comped the whole table's entrees. Big night though, 247 covers. Also the POS terminal at station 3 is frozen again, needs a full restart. Oh and heads up, we have a 20-top VIP coming in tomorrow at 7, it's the Brennan anniversary party, they want the private dining room set with candles and the special menu.",
                audioDuration: 47,
                summary: "Busy closing with 247 covers. Salmon 86'd due to supplier shortage. Walk-in compressor issue recurring (3rd time). Comped table 14 for hair in pasta. POS station 3 frozen. VIP 20-top Brennan party tomorrow at 7pm.",
                categorizedItems: [
                    CategorizedItem(category: .eightySixed, categoryTemplateId: "cat_86", content: "Salmon — supplier shorted delivery, 86'd at 8pm", urgency: .nextShift),
                    CategorizedItem(category: .equipment, categoryTemplateId: "cat_equip", content: "Walk-in compressor making noise again — 3rd time this week", urgency: .immediate),
                    CategorizedItem(category: .equipment, categoryTemplateId: "cat_equip", content: "POS terminal station 3 frozen, needs full restart", urgency: .nextShift),
                    CategorizedItem(category: .guestIssue, categoryTemplateId: "cat_guest", content: "Table 14 — hair in pasta, comped all entrees", urgency: .fyi),
                    CategorizedItem(category: .reservation, categoryTemplateId: "cat_reso", content: "Brennan anniversary party — 20-top VIP, tomorrow 7pm, private dining room", urgency: .immediate)
                ],
                actionItems: [
                    ActionItem(task: "Call seafood supplier re: salmon shortage", category: .eightySixed, categoryTemplateId: "cat_86", urgency: .nextShift, assignee: "Sarah Chen"),
                    ActionItem(task: "Schedule walk-in compressor repair — recurring issue", category: .equipment, categoryTemplateId: "cat_equip", urgency: .immediate),
                    ActionItem(task: "Restart POS terminal station 3", category: .equipment, categoryTemplateId: "cat_equip", urgency: .nextShift),
                    ActionItem(task: "Set up private dining room for Brennan party — candles, special menu", category: .reservation, categoryTemplateId: "cat_reso", urgency: .immediate)
                ],
                acknowledgments: [
                    Acknowledgment(userId: "user_002", userName: "Sarah Chen", timestamp: hoursAgo(1))
                ],
                createdAt: hoursAgo(3)
            ),

            ShiftNote(
                id: "note_002",
                authorId: "user_002", authorName: "Sarah Chen", authorInitials: "SC",
                locationId: "loc_001", shiftType: .mid, shiftTemplateId: "shift_mid",
                rawTranscript: "Mid shift update. Lunch was solid, 89 covers. The new server Kayla is doing great, really picking up the floor fast. FYI the ice machine is leaking again by the service station, put a bucket under it for now. Health inspector is scheduled for next Tuesday, need to make sure all temp logs are current. Also restocked the bar with the wine delivery that came in.",
                audioDuration: 32,
                summary: "Solid lunch with 89 covers. New server Kayla performing well. Ice machine leaking at service station. Health inspector Tuesday — ensure temp logs current. Wine delivery restocked.",
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
                    Acknowledgment(userId: "user_003", userName: "Devon Williams", timestamp: hoursAgo(5)),
                    Acknowledgment(userId: "user_004", userName: "Ava Torres", timestamp: hoursAgo(4))
                ],
                createdAt: hoursAgo(8)
            ),

            ShiftNote(
                id: "note_003",
                authorId: "user_004", authorName: "Ava Torres", authorInitials: "AT",
                locationId: "loc_001", shiftType: .opening, shiftTemplateId: "shift_open",
                rawTranscript: "Opening notes. Everything looks good from last night's close, Devon did a great job. Fryer oil in station 2 needs to be changed, it's getting dark. We're low on to-go containers, the medium ones. Produce delivery came in fine, everything looks fresh. Reminder that the Brennan party is tonight so we need all hands on deck.",
                audioDuration: 28,
                summary: "Clean open after last night. Fryer oil station 2 needs changing. Low on medium to-go containers. Produce delivery good. Brennan VIP party tonight.",
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
                createdAt: hoursAgo(14)
            ),

            ShiftNote(
                id: "note_004",
                authorId: "user_005", authorName: "James Park", authorInitials: "JP",
                locationId: "loc_002", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Closing at Saltwater. Wild night, 198 covers for a Wednesday. We ran out of the lobster bisque by 7:30, had to 86 it. Two comps tonight, table 6 had an undercooked steak sent back twice, table 22 birthday dessert was forgotten. Dishwasher running slow, drain may need cleaning. Back door lock sticking again.",
                audioDuration: 41,
                summary: "Busy Wednesday with 198 covers. Lobster bisque 86'd at 7:30. Two comps (undercooked steak, missed birthday). Dishwasher slow. Back door lock sticking.",
                categorizedItems: [
                    CategorizedItem(category: .eightySixed, categoryTemplateId: "cat_86", content: "Lobster bisque ran out by 7:30pm", urgency: .nextShift),
                    CategorizedItem(category: .guestIssue, categoryTemplateId: "cat_guest", content: "Table 6 — undercooked steak sent back twice, comped meals", urgency: .fyi),
                    CategorizedItem(category: .guestIssue, categoryTemplateId: "cat_guest", content: "Table 22 — forgot birthday dessert, comped champagne", urgency: .fyi),
                    CategorizedItem(category: .equipment, categoryTemplateId: "cat_equip", content: "Dishwasher running slow — drain may need cleaning", urgency: .thisWeek),
                    CategorizedItem(category: .maintenance, categoryTemplateId: "cat_maint", content: "Back door lock sticking again", urgency: .thisWeek)
                ],
                actionItems: [
                    ActionItem(task: "Prep extra lobster bisque for tomorrow", category: .eightySixed, categoryTemplateId: "cat_86", urgency: .nextShift),
                    ActionItem(task: "Clean dishwasher drain", category: .equipment, categoryTemplateId: "cat_equip", urgency: .thisWeek),
                    ActionItem(task: "Fix back door lock", category: .maintenance, categoryTemplateId: "cat_maint", urgency: .thisWeek)
                ],
                acknowledgments: [],
                createdAt: hoursAgo(2)
            ),

            ShiftNote(
                id: "note_005",
                authorId: "user_007", authorName: "Carlos Mendez", authorInitials: "CM",
                locationId: "loc_003", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Rooftop closing notes. Slow night due to rain, only 67 covers. Outdoor heaters on the east side are out, two of them won't ignite. Beer delivery was short, missing the IPA kegs. Had to cut Happy Hour early because we ran out of the well tequila. No major issues otherwise, clean close.",
                audioDuration: 25,
                summary: "Slow rainy night, 67 covers. Two east-side heaters out. Missing IPA kegs. Well tequila ran out early.",
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
                createdAt: hoursAgo(1)
            ),

            ShiftNote(
                id: "note_006",
                authorId: "user_003", authorName: "Devon Williams", authorInitials: "DW",
                locationId: "loc_001", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Another solid closing tonight. 212 covers, good energy. The flat top on station 1 has a hot spot on the left side, burns anything you put there. Server Marco called out sick for tomorrow morning, need someone to cover. The draft system on tap 4 is pouring foamy, needs to be rebalanced. Also we got a 5-star review from the couple on table 9, they loved the tasting menu.",
                audioDuration: 38,
                summary: "212 covers. Flat top station 1 has hot spot. Marco out tomorrow AM — need cover. Tap 4 draft foamy. 5-star review from tasting menu couple.",
                categorizedItems: [
                    CategorizedItem(category: .equipment, content: "Flat top station 1 has a hot spot on left side — burning food", urgency: .immediate),
                    CategorizedItem(category: .staffNote, content: "Server Marco called out sick tomorrow AM — need coverage", urgency: .immediate),
                    CategorizedItem(category: .equipment, content: "Draft tap 4 pouring foamy — needs rebalancing", urgency: .nextShift),
                    CategorizedItem(category: .general, content: "5-star review from table 9 couple — loved tasting menu", urgency: .fyi)
                ],
                actionItems: [
                    ActionItem(task: "Get flat top station 1 inspected — hot spot issue", category: .equipment, urgency: .immediate),
                    ActionItem(task: "Find AM coverage for Marco's shift tomorrow", category: .staffNote, urgency: .immediate),
                    ActionItem(task: "Rebalance draft system on tap 4", category: .equipment, urgency: .nextShift)
                ],
                acknowledgments: [
                    Acknowledgment(userId: "user_002", userName: "Sarah Chen", timestamp: hoursAgo(25))
                ],
                createdAt: hoursAgo(27)
            ),

            ShiftNote(
                id: "note_007",
                authorId: "user_002", authorName: "Sarah Chen", authorInitials: "SC",
                locationId: "loc_001", shiftType: .opening, shiftTemplateId: "shift_open",
                rawTranscript: "Morning update. Walk-in temp was at 41 degrees when I checked, should be 38. Moved it down. Bread delivery came in short — only got 40 baguettes instead of 60. Prepped extra risotto base since we ran out last Friday. New host training starts at 11.",
                audioDuration: 22,
                summary: "Walk-in temp high (41°F, adjusted). Bread delivery short by 20 baguettes. Extra risotto base prepped. New host training at 11.",
                categorizedItems: [
                    CategorizedItem(category: .healthSafety, content: "Walk-in temperature at 41°F — adjusted to 38°F target", urgency: .immediate),
                    CategorizedItem(category: .inventory, content: "Bread delivery short — 40 baguettes instead of 60", urgency: .nextShift),
                    CategorizedItem(category: .general, content: "Extra risotto base prepped after last Friday's shortage", urgency: .fyi),
                    CategorizedItem(category: .staffNote, content: "New host training starts at 11am", urgency: .fyi)
                ],
                actionItems: [
                    ActionItem(task: "Monitor walk-in temperature — log readings every 2 hours", category: .healthSafety, urgency: .immediate),
                    ActionItem(task: "Contact bakery about bread shortage", category: .inventory, urgency: .nextShift)
                ],
                acknowledgments: [
                    Acknowledgment(userId: "user_003", userName: "Devon Williams", timestamp: hoursAgo(36)),
                    Acknowledgment(userId: "user_004", userName: "Ava Torres", timestamp: hoursAgo(35))
                ],
                createdAt: hoursAgo(38)
            ),

            ShiftNote(
                id: "note_008",
                authorId: "user_004", authorName: "Ava Torres", authorInitials: "AT",
                locationId: "loc_001", shiftType: .mid, shiftTemplateId: "shift_mid",
                rawTranscript: "Quick mid update. We're running low on gluten-free pasta, maybe 6 portions left. The espresso machine pressure is dropping, might need descaling. Had a walkout on table 3, party of 4, no payment. Got their faces on camera though.",
                audioDuration: 19,
                summary: "Low on GF pasta (6 portions). Espresso machine pressure dropping. Walkout table 3 party of 4 — on camera.",
                categorizedItems: [
                    CategorizedItem(category: .inventory, content: "Gluten-free pasta running low — ~6 portions remaining", urgency: .nextShift),
                    CategorizedItem(category: .equipment, content: "Espresso machine pressure dropping — may need descaling", urgency: .thisWeek),
                    CategorizedItem(category: .incident, content: "Walkout on table 3, party of 4 — captured on security camera", urgency: .immediate)
                ],
                actionItems: [
                    ActionItem(task: "Order gluten-free pasta — emergency restock", category: .inventory, urgency: .nextShift),
                    ActionItem(task: "Schedule espresso machine descaling", category: .equipment, urgency: .thisWeek),
                    ActionItem(task: "File incident report for table 3 walkout — pull camera footage", category: .incident, urgency: .immediate, status: .inProgress, assignee: "Devon Williams")
                ],
                createdAt: hoursAgo(32)
            ),

            ShiftNote(
                id: "note_009",
                authorId: "user_006", authorName: "Nia Johnson", authorInitials: "NJ",
                locationId: "loc_002", shiftType: .mid, shiftTemplateId: "shift_mid",
                rawTranscript: "Saltwater mid shift. Lunch patio was packed, 94 covers before 2pm. The oyster delivery came in and 2 dozen were already dead, sent them back. Line cook Ricky cut his finger, minor, first aid applied and he's back on the line. The hood vent over station 3 isn't pulling well, getting smoky. We need to reprint the dessert menus, several are stained.",
                audioDuration: 35,
                summary: "Packed patio lunch, 94 covers. Bad oysters returned (2 dozen). Minor cut for Ricky — first aid done. Hood vent station 3 weak. Dessert menus need reprinting.",
                categorizedItems: [
                    CategorizedItem(category: .inventory, content: "2 dozen dead oysters in delivery — sent back to supplier", urgency: .nextShift),
                    CategorizedItem(category: .healthSafety, content: "Line cook Ricky minor finger cut — first aid applied, back on line", urgency: .fyi),
                    CategorizedItem(category: .equipment, content: "Hood vent station 3 not pulling properly — getting smoky", urgency: .thisWeek),
                    CategorizedItem(category: .general, content: "Dessert menus stained — need reprinting", urgency: .thisWeek)
                ],
                actionItems: [
                    ActionItem(task: "File complaint with oyster supplier — 2 dozen dead on arrival", category: .inventory, urgency: .nextShift),
                    ActionItem(task: "Schedule hood vent cleaning/inspection for station 3", category: .equipment, urgency: .thisWeek),
                    ActionItem(task: "Reprint dessert menus", category: .general, urgency: .thisWeek)
                ],
                createdAt: hoursAgo(10)
            ),

            ShiftNote(
                id: "note_010",
                authorId: "user_005", authorName: "James Park", authorInitials: "JP",
                locationId: "loc_002", shiftType: .opening, shiftTemplateId: "shift_open",
                rawTranscript: "Saltwater opening. Floors were sticky near the bar, closing crew didn't mop properly. Dairy delivery is late, still waiting. The outdoor umbrellas need new fabric, two are torn. Reservation system shows we're booked solid for Saturday brunch, 120 covers expected.",
                audioDuration: 20,
                summary: "Sticky floors near bar (closing crew). Dairy delivery late. Two outdoor umbrellas torn. Saturday brunch booked solid — 120 covers.",
                categorizedItems: [
                    CategorizedItem(category: .general, content: "Floors sticky near bar — closing crew didn't mop properly", urgency: .nextShift),
                    CategorizedItem(category: .inventory, content: "Dairy delivery late — still waiting", urgency: .immediate),
                    CategorizedItem(category: .maintenance, content: "Two outdoor umbrellas have torn fabric", urgency: .thisWeek),
                    CategorizedItem(category: .reservation, content: "Saturday brunch booked solid — 120 covers expected", urgency: .nextShift)
                ],
                actionItems: [
                    ActionItem(task: "Follow up on dairy delivery status", category: .inventory, urgency: .immediate, status: .resolved),
                    ActionItem(task: "Order replacement umbrella fabric", category: .maintenance, urgency: .thisWeek),
                    ActionItem(task: "Prep extra brunch items for Saturday's 120-cover booking", category: .reservation, urgency: .nextShift)
                ],
                createdAt: hoursAgo(56)
            ),

            ShiftNote(
                id: "note_011",
                authorId: "user_007", authorName: "Carlos Mendez", authorInitials: "CM",
                locationId: "loc_003", shiftType: .opening, shiftTemplateId: "shift_open",
                rawTranscript: "Rooftop opening. Sound system speaker on the west side is blown. Need to order new cocktail napkins with the updated logo. The elevator inspection certificate expired last week, need to get that renewed ASAP. Otherwise clean open.",
                audioDuration: 18,
                summary: "West speaker blown. Need new logo cocktail napkins. Elevator inspection certificate expired — renew urgently.",
                categorizedItems: [
                    CategorizedItem(category: .equipment, content: "Sound system speaker (west side) blown out", urgency: .nextShift),
                    CategorizedItem(category: .inventory, content: "Need new cocktail napkins with updated logo", urgency: .thisWeek),
                    CategorizedItem(category: .healthSafety, content: "Elevator inspection certificate expired last week", urgency: .immediate)
                ],
                actionItems: [
                    ActionItem(task: "Replace west-side speaker", category: .equipment, urgency: .nextShift),
                    ActionItem(task: "Order cocktail napkins with new logo", category: .inventory, urgency: .thisWeek),
                    ActionItem(task: "Schedule elevator inspection renewal — certificate expired", category: .healthSafety, urgency: .immediate)
                ],
                createdAt: hoursAgo(50)
            ),

            ShiftNote(
                id: "note_012",
                authorId: "user_003", authorName: "Devon Williams", authorInitials: "DW",
                locationId: "loc_001", shiftType: .mid, shiftTemplateId: "shift_mid",
                rawTranscript: "Mid shift. Slow lunch, only 52 covers but we made up for it with high ticket averages. The exhaust fan in the prep area is vibrating badly. Catering order for the Thompson wedding Saturday is confirmed — 150 guests, need to start prep Thursday. Bartender Lisa wants to introduce a new fall cocktail menu, she's got some great ideas.",
                audioDuration: 26,
                summary: "Slow lunch, 52 covers but high averages. Prep area exhaust fan vibrating. Thompson wedding catering Saturday (150 guests). Lisa proposing fall cocktail menu.",
                categorizedItems: [
                    CategorizedItem(category: .equipment, content: "Prep area exhaust fan vibrating badly", urgency: .thisWeek),
                    CategorizedItem(category: .reservation, content: "Thompson wedding catering Saturday — 150 guests, start prep Thursday", urgency: .nextShift),
                    CategorizedItem(category: .staffNote, content: "Bartender Lisa wants to introduce fall cocktail menu — has ideas ready", urgency: .fyi)
                ],
                actionItems: [
                    ActionItem(task: "Get exhaust fan in prep area inspected", category: .equipment, urgency: .thisWeek),
                    ActionItem(task: "Begin Thompson wedding prep Thursday — 150 guests", category: .reservation, urgency: .nextShift),
                    ActionItem(task: "Schedule tasting session for Lisa's fall cocktail menu", category: .staffNote, urgency: .thisWeek)
                ],
                createdAt: hoursAgo(56)
            ),

            ShiftNote(
                id: "note_013",
                authorId: "user_004", authorName: "Ava Torres", authorInitials: "AT",
                locationId: "loc_001", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Big closing tonight. 278 covers, new record for a Thursday. We ran through all the ribeye by 8:45, also low on the duck confit. Bathroom on the second floor has a running toilet, super loud. Two servers got into an argument during service, pulled them aside after — it's handled but worth noting. Celebrity diner tonight, won't say who but they requested total privacy and tipped 40 percent.",
                audioDuration: 44,
                summary: "Record Thursday: 278 covers. Ribeye sold out 8:45pm, duck confit low. 2nd floor toilet running. Server conflict handled. Celebrity diner — privacy, 40% tip.",
                categorizedItems: [
                    CategorizedItem(category: .eightySixed, content: "Ribeye sold out by 8:45pm — 278-cover night", urgency: .nextShift),
                    CategorizedItem(category: .eightySixed, content: "Duck confit running very low", urgency: .nextShift),
                    CategorizedItem(category: .maintenance, content: "Second floor bathroom toilet running — very loud", urgency: .thisWeek),
                    CategorizedItem(category: .staffNote, content: "Two servers had argument during service — pulled aside, resolved", urgency: .fyi),
                    CategorizedItem(category: .reservation, content: "Celebrity diner requested total privacy — 40% tip", urgency: .fyi)
                ],
                actionItems: [
                    ActionItem(task: "Order extra ribeye for weekend — Thursday sold out", category: .eightySixed, urgency: .nextShift),
                    ActionItem(task: "Prep additional duck confit", category: .eightySixed, urgency: .nextShift),
                    ActionItem(task: "Fix running toilet — 2nd floor bathroom", category: .maintenance, urgency: .thisWeek, assignee: "Devon Williams")
                ],
                acknowledgments: [
                    Acknowledgment(userId: "user_001", userName: "Marcus Rivera", timestamp: hoursAgo(49)),
                    Acknowledgment(userId: "user_002", userName: "Sarah Chen", timestamp: hoursAgo(48))
                ],
                createdAt: hoursAgo(51)
            ),

            ShiftNote(
                id: "note_014",
                authorId: "user_005", authorName: "James Park", authorInitials: "JP",
                locationId: "loc_002", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Saltwater closing. 156 covers, solid Tuesday. The raw bar display fridge temp is fluctuating between 36 and 42, not consistent. Manager special board is running low on dry erase markers. Server Taylor's last day is Friday, we should do something. Had a dine-and-dash attempt but the hostess caught them at the door.",
                audioDuration: 30,
                summary: "156 covers. Raw bar fridge temp fluctuating (36-42°F). Dry erase markers low. Taylor's last day Friday. Dine-and-dash attempt caught.",
                categorizedItems: [
                    CategorizedItem(category: .equipment, content: "Raw bar display fridge temp fluctuating 36-42°F — inconsistent", urgency: .immediate),
                    CategorizedItem(category: .inventory, content: "Specials board running low on dry erase markers", urgency: .thisWeek),
                    CategorizedItem(category: .staffNote, content: "Server Taylor's last day is Friday — plan something", urgency: .thisWeek),
                    CategorizedItem(category: .incident, content: "Dine-and-dash attempt — hostess caught them at door", urgency: .fyi)
                ],
                actionItems: [
                    ActionItem(task: "Get raw bar fridge serviced — temp fluctuating dangerously", category: .equipment, urgency: .immediate),
                    ActionItem(task: "Order dry erase markers", category: .inventory, urgency: .thisWeek, status: .resolved),
                    ActionItem(task: "Plan farewell for Taylor — last day Friday", category: .staffNote, urgency: .thisWeek)
                ],
                createdAt: hoursAgo(26)
            ),

            ShiftNote(
                id: "note_015",
                authorId: "user_006", authorName: "Nia Johnson", authorInitials: "NJ",
                locationId: "loc_002", shiftType: .opening, shiftTemplateId: "shift_open",
                rawTranscript: "Quick opening notes. Everything looked clean. The fish delivery is coming at 10 instead of 8 today. We're out of lemons completely. New table numbers arrived, need to swap them out before lunch.",
                audioDuration: 15,
                summary: "Clean open. Fish delivery delayed to 10am. Out of lemons. New table numbers arrived.",
                categorizedItems: [
                    CategorizedItem(category: .inventory, content: "Fish delivery delayed — coming at 10am instead of 8am", urgency: .nextShift),
                    CategorizedItem(category: .inventory, content: "Completely out of lemons", urgency: .immediate),
                    CategorizedItem(category: .general, content: "New table numbers arrived — need to swap before lunch", urgency: .nextShift)
                ],
                actionItems: [
                    ActionItem(task: "Emergency lemon run — we're completely out", category: .inventory, urgency: .immediate, status: .resolved),
                    ActionItem(task: "Swap out old table numbers before lunch service", category: .general, urgency: .nextShift, status: .resolved)
                ],
                createdAt: hoursAgo(80)
            ),

            ShiftNote(
                id: "note_016",
                authorId: "user_007", authorName: "Carlos Mendez", authorInitials: "CM",
                locationId: "loc_003", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Long closing at Rooftop. 189 covers, great night. We had a large bachelorette party, 16 people, they were loud but tipped well. The rooftop railing on the north side has a loose bolt, safety concern. Restroom soap dispensers are both empty downstairs. The DJ equipment needs a new cable, the left channel is cutting out. Closing inventory shows we're critically low on vodka and gin.",
                audioDuration: 52,
                summary: "189 covers, great night. Bachelorette party of 16. North railing loose bolt (safety). Soap dispensers empty. DJ left channel cutting out. Low on vodka and gin.",
                categorizedItems: [
                    CategorizedItem(category: .reservation, content: "Bachelorette party of 16 — loud but great tips", urgency: .fyi),
                    CategorizedItem(category: .healthSafety, content: "North side rooftop railing has a loose bolt — safety hazard", urgency: .immediate),
                    CategorizedItem(category: .maintenance, content: "Downstairs restroom soap dispensers both empty", urgency: .nextShift),
                    CategorizedItem(category: .equipment, content: "DJ equipment left channel cutting out — needs new cable", urgency: .thisWeek),
                    CategorizedItem(category: .inventory, content: "Critically low on vodka and gin", urgency: .immediate)
                ],
                actionItems: [
                    ActionItem(task: "Fix loose bolt on north railing ASAP — safety issue", category: .healthSafety, urgency: .immediate),
                    ActionItem(task: "Refill soap dispensers in downstairs restrooms", category: .maintenance, urgency: .nextShift),
                    ActionItem(task: "Order replacement DJ cable", category: .equipment, urgency: .thisWeek),
                    ActionItem(task: "Emergency spirits order — vodka and gin critically low", category: .inventory, urgency: .immediate)
                ],
                voiceReplies: [
                    VoiceReply(authorId: "user_001", authorName: "Marcus Rivera", transcript: "I'll call the contractor about the railing first thing tomorrow. Don't let anyone lean on that section tonight.", timestamp: hoursAgo(24))
                ],
                createdAt: hoursAgo(25)
            ),

            ShiftNote(
                id: "note_017",
                authorId: "user_002", authorName: "Sarah Chen", authorInitials: "SC",
                locationId: "loc_001", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Closing update. 185 covers. The pasta maker is jamming on the linguine setting, works fine for everything else. We're almost out of truffle oil, maybe 2 services worth. Got a complaint from the building about our dumpster area, says it's attracting rats. Need to address that. The new menu cards look great, customers are responding well.",
                audioDuration: 33,
                summary: "185 covers. Pasta maker jamming on linguine. Low truffle oil (2 services). Building complaint about dumpster/rats. New menu cards well received.",
                categorizedItems: [
                    CategorizedItem(category: .equipment, content: "Pasta maker jamming on linguine setting — other settings fine", urgency: .thisWeek),
                    CategorizedItem(category: .inventory, content: "Truffle oil nearly out — ~2 services remaining", urgency: .nextShift),
                    CategorizedItem(category: .healthSafety, content: "Building management complaint: dumpster area attracting rats", urgency: .immediate),
                    CategorizedItem(category: .general, content: "New menu cards getting positive customer feedback", urgency: .fyi)
                ],
                actionItems: [
                    ActionItem(task: "Service pasta maker — linguine setting jamming", category: .equipment, urgency: .thisWeek),
                    ActionItem(task: "Order truffle oil — 2 services left", category: .inventory, urgency: .nextShift, assignee: "Ava Torres"),
                    ActionItem(task: "Clean dumpster area and schedule pest control", category: .healthSafety, urgency: .immediate)
                ],
                acknowledgments: [
                    Acknowledgment(userId: "user_003", userName: "Devon Williams", timestamp: hoursAgo(73))
                ],
                createdAt: hoursAgo(75)
            ),

            ShiftNote(
                id: "note_018",
                authorId: "user_003", authorName: "Devon Williams", authorInitials: "DW",
                locationId: "loc_001", shiftType: .opening, shiftTemplateId: "shift_open",
                rawTranscript: "Opening. Everything's prepped well from last night. The CO2 tank for the soda system is getting low, probably one more day. Two reservations cancelled for tonight's chef's table. The AC unit in the private dining room is blowing warm air. Also reminder: staff meeting Monday at 3pm.",
                audioDuration: 24,
                summary: "Good prep from last night. CO2 tank low (1 day). Two chef's table cancellations. PDR AC blowing warm. Staff meeting Monday 3pm.",
                categorizedItems: [
                    CategorizedItem(category: .inventory, content: "CO2 tank for soda system getting low — ~1 day remaining", urgency: .nextShift),
                    CategorizedItem(category: .reservation, content: "Two chef's table reservations cancelled for tonight", urgency: .fyi),
                    CategorizedItem(category: .equipment, content: "Private dining room AC blowing warm air", urgency: .immediate),
                    CategorizedItem(category: .staffNote, content: "Staff meeting Monday at 3pm", urgency: .fyi)
                ],
                actionItems: [
                    ActionItem(task: "Order CO2 tank replacement — 1 day left on soda system", category: .inventory, urgency: .nextShift),
                    ActionItem(task: "Fix AC in private dining room — blowing warm", category: .equipment, urgency: .immediate)
                ],
                createdAt: hoursAgo(62)
            ),

            ShiftNote(
                id: "note_019",
                authorId: "user_005", authorName: "James Park", authorInitials: "JP",
                locationId: "loc_002", shiftType: .mid, shiftTemplateId: "shift_mid",
                rawTranscript: "Saltwater mid update. Brunch was insane, 142 covers. Bottomless mimosa promo is too popular, we went through 9 cases of prosecco. The patio awning is stuck halfway, can't retract fully. One of the bartenders dropped a full bottle of Hendrick's, that's 80 bucks gone. Server scheduling for next week needs attention, we're understaffed Saturday.",
                audioDuration: 29,
                summary: "Insane brunch, 142 covers. Mimosa promo used 9 cases prosecco. Patio awning stuck. Dropped Hendrick's ($80). Saturday understaffed.",
                categorizedItems: [
                    CategorizedItem(category: .inventory, content: "Bottomless mimosa promo burned through 9 cases of prosecco", urgency: .nextShift),
                    CategorizedItem(category: .maintenance, content: "Patio awning stuck halfway — can't fully retract", urgency: .thisWeek),
                    CategorizedItem(category: .incident, content: "Bartender dropped full Hendrick's bottle — $80 loss", urgency: .fyi),
                    CategorizedItem(category: .staffNote, content: "Saturday schedule understaffed — need more coverage", urgency: .immediate)
                ],
                actionItems: [
                    ActionItem(task: "Order extra prosecco for mimosa promo", category: .inventory, urgency: .nextShift),
                    ActionItem(task: "Get patio awning mechanism serviced", category: .maintenance, urgency: .thisWeek),
                    ActionItem(task: "Fill Saturday schedule gaps — need 2 more servers", category: .staffNote, urgency: .immediate)
                ],
                createdAt: hoursAgo(34)
            ),

            ShiftNote(
                id: "note_020",
                authorId: "user_004", authorName: "Ava Torres", authorInitials: "AT",
                locationId: "loc_001", shiftType: .mid, shiftTemplateId: "shift_mid",
                rawTranscript: "Quick mid update Ember Room. Lunch was 76 covers. The reservation system went down for about 20 minutes around noon, we used the paper backup. All good now. Prep cook Miguel is requesting next Friday off. The wine by the glass Chardonnay is almost kicked.",
                audioDuration: 21,
                summary: "76 covers. Reservation system down 20 min (paper backup used). Miguel requesting Friday off. Chardonnay BTG almost out.",
                categorizedItems: [
                    CategorizedItem(category: .equipment, content: "Reservation system went down ~20 min at noon — paper backup used", urgency: .thisWeek),
                    CategorizedItem(category: .staffNote, content: "Prep cook Miguel requesting next Friday off", urgency: .thisWeek),
                    CategorizedItem(category: .inventory, content: "Chardonnay by-the-glass almost kicked", urgency: .nextShift)
                ],
                actionItems: [
                    ActionItem(task: "Check reservation system stability — had 20-min outage", category: .equipment, urgency: .thisWeek),
                    ActionItem(task: "Process Miguel's Friday PTO request", category: .staffNote, urgency: .thisWeek),
                    ActionItem(task: "Swap Chardonnay BTG keg — almost empty", category: .inventory, urgency: .nextShift)
                ],
                createdAt: hoursAgo(8)
            ),

            ShiftNote(
                id: "note_021",
                authorId: "user_006", authorName: "Nia Johnson", authorInitials: "NJ",
                locationId: "loc_002", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Saltwater closing. 171 covers, strong Monday. The grease trap is backing up, starting to smell. We absolutely need to get that cleaned this week. Hostess stand iPad screen is cracked, still works but looks bad. Had two food allergy incidents tonight — both handled properly with the allergy protocol. Remind the team to ALWAYS ask about allergies.",
                audioDuration: 37,
                summary: "171 covers. Grease trap backing up/smelling. Hostess iPad cracked. Two allergy incidents — protocol followed.",
                categorizedItems: [
                    CategorizedItem(category: .maintenance, content: "Grease trap backing up and starting to smell", urgency: .immediate),
                    CategorizedItem(category: .equipment, content: "Hostess stand iPad screen cracked — functional but looks bad", urgency: .thisWeek),
                    CategorizedItem(category: .healthSafety, content: "Two food allergy incidents tonight — allergy protocol followed correctly", urgency: .fyi),
                    CategorizedItem(category: .staffNote, content: "Remind team to ALWAYS ask about allergies upfront", urgency: .nextShift)
                ],
                actionItems: [
                    ActionItem(task: "Schedule grease trap cleaning THIS WEEK — backing up", category: .maintenance, urgency: .immediate),
                    ActionItem(task: "Replace hostess stand iPad or get screen fixed", category: .equipment, urgency: .thisWeek),
                    ActionItem(task: "Send allergy protocol reminder to all staff", category: .healthSafety, urgency: .nextShift)
                ],
                createdAt: hoursAgo(50)
            ),

            ShiftNote(
                id: "note_022",
                authorId: "user_007", authorName: "Carlos Mendez", authorInitials: "CM",
                locationId: "loc_003", shiftType: .mid, shiftTemplateId: "shift_mid",
                rawTranscript: "Rooftop mid shift. Light crowd, 38 covers, typical weekday lunch. The water feature fountain pump died. Plants on the south terrace need watering badly. Otherwise quiet.",
                audioDuration: 15,
                summary: "Light lunch, 38 covers. Fountain pump died. South terrace plants need watering.",
                categorizedItems: [
                    CategorizedItem(category: .maintenance, content: "Water feature fountain pump died", urgency: .thisWeek),
                    CategorizedItem(category: .maintenance, content: "South terrace plants wilting — need watering urgently", urgency: .nextShift)
                ],
                actionItems: [
                    ActionItem(task: "Replace fountain pump", category: .maintenance, urgency: .thisWeek),
                    ActionItem(task: "Water south terrace plants — they're wilting", category: .maintenance, urgency: .nextShift, status: .resolved)
                ],
                createdAt: hoursAgo(73)
            ),

            ShiftNote(
                id: "note_023",
                authorId: "user_002", authorName: "Sarah Chen", authorInitials: "SC",
                locationId: "loc_001", shiftType: .mid, shiftTemplateId: "shift_mid",
                rawTranscript: "Ember Room mid shift. 98 covers for lunch, above average. The hand dryer in the men's room stopped working. We received the new glassware shipment but 12 of the wine glasses arrived broken. Need to file a claim. Line cook position still open, we've had 3 interviews but no one's been right. The community board inspector stopped by and our permit is up to date, so that's good.",
                audioDuration: 42,
                summary: "98 covers. Men's room hand dryer broken. 12 wine glasses arrived broken — file claim. Line cook position still open. Permit confirmed current.",
                categorizedItems: [
                    CategorizedItem(category: .maintenance, content: "Men's room hand dryer stopped working", urgency: .thisWeek),
                    CategorizedItem(category: .inventory, content: "12 wine glasses from new shipment arrived broken — need claim", urgency: .nextShift),
                    CategorizedItem(category: .staffNote, content: "Line cook position open — 3 interviews done, no hire yet", urgency: .thisWeek),
                    CategorizedItem(category: .general, content: "Community board inspector confirmed permit is current", urgency: .fyi)
                ],
                actionItems: [
                    ActionItem(task: "Fix men's room hand dryer", category: .maintenance, urgency: .thisWeek),
                    ActionItem(task: "File damage claim for 12 broken wine glasses", category: .inventory, urgency: .nextShift),
                    ActionItem(task: "Schedule more line cook interviews — still need to fill position", category: .staffNote, urgency: .thisWeek)
                ],
                createdAt: hoursAgo(56)
            ),

            ShiftNote(
                id: "note_024",
                authorId: "user_003", authorName: "Devon Williams", authorInitials: "DW",
                locationId: "loc_001", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Ember Room Friday closing. Incredible night, 301 covers. Set a new all-time record. Kitchen handled it like champs. We did run out of the chocolate lava cake and the sea bass. The printer at station 2 ran out of paper mid-rush, chaos for about 10 minutes. Grease on the floor near the fryer station, someone almost slipped. Cleaned it up immediately. Private event inquiry for December 15th, 80 guests.",
                audioDuration: 31,
                summary: "ALL-TIME RECORD: 301 covers! 86'd chocolate lava cake & sea bass. Station 2 printer out mid-rush. Grease spill near fryer (cleaned). Dec 15 event inquiry, 80 guests.",
                categorizedItems: [
                    CategorizedItem(category: .eightySixed, content: "Chocolate lava cake sold out — record 301-cover night", urgency: .nextShift),
                    CategorizedItem(category: .eightySixed, content: "Sea bass sold out", urgency: .nextShift),
                    CategorizedItem(category: .equipment, content: "Station 2 printer ran out of paper mid-rush — 10 min disruption", urgency: .nextShift),
                    CategorizedItem(category: .healthSafety, content: "Grease spill near fryer — someone nearly slipped, cleaned immediately", urgency: .fyi),
                    CategorizedItem(category: .reservation, content: "Private event inquiry: December 15th, 80 guests", urgency: .thisWeek)
                ],
                actionItems: [
                    ActionItem(task: "Double prep on chocolate lava cake and sea bass for next weekend", category: .eightySixed, urgency: .nextShift, status: .resolved),
                    ActionItem(task: "Stock extra printer paper at all stations", category: .equipment, urgency: .nextShift, status: .resolved),
                    ActionItem(task: "Follow up on December 15th private event — 80 guests", category: .reservation, urgency: .thisWeek)
                ],
                acknowledgments: [
                    Acknowledgment(userId: "user_001", userName: "Marcus Rivera", timestamp: hoursAgo(97)),
                    Acknowledgment(userId: "user_002", userName: "Sarah Chen", timestamp: hoursAgo(96)),
                    Acknowledgment(userId: "user_004", userName: "Ava Torres", timestamp: hoursAgo(95))
                ],
                createdAt: hoursAgo(99)
            ),

            ShiftNote(
                id: "note_025",
                authorId: "user_005", authorName: "James Park", authorInitials: "JP",
                locationId: "loc_002", shiftType: .closing, shiftTemplateId: "shift_close",
                rawTranscript: "Saltwater Thursday closing. 167 covers. The clam chowder batch was off today, pulled it from the menu at 6pm. Wine fridge door seal is coming loose on the left side. The new cocktail menu is a hit, especially the smoked old fashioned. Server training session needed on the new POS update that's coming Monday.",
                audioDuration: 28,
                summary: "167 covers. Clam chowder pulled 6pm (off batch). Wine fridge door seal loose. New cocktails popular. POS training needed Monday.",
                categorizedItems: [
                    CategorizedItem(category: .eightySixed, content: "Clam chowder pulled from menu at 6pm — off batch", urgency: .nextShift),
                    CategorizedItem(category: .equipment, content: "Wine fridge left door seal coming loose", urgency: .thisWeek),
                    CategorizedItem(category: .general, content: "New cocktail menu a hit — smoked old fashioned very popular", urgency: .fyi),
                    CategorizedItem(category: .staffNote, content: "POS update Monday — staff needs training session", urgency: .nextShift)
                ],
                actionItems: [
                    ActionItem(task: "Review clam chowder recipe/process — batch was off", category: .eightySixed, urgency: .nextShift),
                    ActionItem(task: "Fix wine fridge door seal — left side", category: .equipment, urgency: .thisWeek),
                    ActionItem(task: "Schedule POS update training before Monday", category: .staffNote, urgency: .nextShift)
                ],
                createdAt: hoursAgo(74)
            ),
        ]
    }

    static let recurringIssues: [RecurringIssue] = {
        let now = Date()
        let cal = Calendar.current
        return [
            RecurringIssue(
                description: "Walk-in compressor making noise",
                category: .equipment, categoryTemplateId: "cat_equip",
                locationId: "loc_001", locationName: "The Ember Room",
                mentionCount: 4, relatedNoteIds: ["note_001"],
                firstMentioned: cal.date(byAdding: .day, value: -12, to: now)!,
                lastMentioned: now
            ),
            RecurringIssue(
                description: "Ice machine leaking at service station",
                category: .maintenance, categoryTemplateId: "cat_maint",
                locationId: "loc_001", locationName: "The Ember Room",
                mentionCount: 3, relatedNoteIds: ["note_002"],
                firstMentioned: cal.date(byAdding: .day, value: -9, to: now)!,
                lastMentioned: cal.date(byAdding: .hour, value: -8, to: now)!
            ),
            RecurringIssue(
                description: "Back door lock sticking",
                category: .maintenance, categoryTemplateId: "cat_maint",
                locationId: "loc_002", locationName: "Saltwater Kitchen",
                mentionCount: 3, relatedNoteIds: ["note_004"],
                firstMentioned: cal.date(byAdding: .day, value: -14, to: now)!,
                lastMentioned: cal.date(byAdding: .hour, value: -2, to: now)!
            ),
            RecurringIssue(
                description: "Outdoor heaters failing to ignite",
                category: .equipment, categoryTemplateId: "cat_equip",
                locationId: "loc_003", locationName: "Rooftop Social",
                mentionCount: 2, relatedNoteIds: ["note_005"],
                firstMentioned: cal.date(byAdding: .day, value: -7, to: now)!,
                lastMentioned: cal.date(byAdding: .hour, value: -1, to: now)!
            ),
            RecurringIssue(
                description: "POS terminal station 3 freezing",
                category: .equipment, categoryTemplateId: "cat_equip",
                locationId: "loc_001", locationName: "The Ember Room",
                mentionCount: 5, relatedNoteIds: ["note_001", "note_020"],
                firstMentioned: cal.date(byAdding: .day, value: -21, to: now)!,
                lastMentioned: cal.date(byAdding: .hour, value: -3, to: now)!
            )
        ]
    }()
}
