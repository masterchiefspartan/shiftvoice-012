import Foundation

nonisolated struct IndustryTemplate: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let icon: String
    let defaultCategories: [CategoryTemplate]
    let defaultShifts: [ShiftTemplate]
    let defaultRoles: [RoleTemplate]
    let terminology: IndustryTerminology

    init(
        id: String,
        name: String,
        icon: String,
        defaultCategories: [CategoryTemplate],
        defaultShifts: [ShiftTemplate],
        defaultRoles: [RoleTemplate],
        terminology: IndustryTerminology
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.defaultCategories = defaultCategories
        self.defaultShifts = defaultShifts
        self.defaultRoles = defaultRoles
        self.terminology = terminology
    }
}

nonisolated struct IndustryTerminology: Codable, Sendable {
    let shiftHandoff: String
    let location: String
    let customer: String
    let outOfStock: String
    let roles: [String]
    let equipment: [String]
    let slang: [String]

    init(
        shiftHandoff: String = "Shift Handoff",
        location: String = "Location",
        customer: String = "Customer",
        outOfStock: String = "Out of Stock",
        roles: [String] = [],
        equipment: [String] = [],
        slang: [String] = []
    ) {
        self.shiftHandoff = shiftHandoff
        self.location = location
        self.customer = customer
        self.outOfStock = outOfStock
        self.roles = roles
        self.equipment = equipment
        self.slang = slang
    }

    var allVocabulary: [String] {
        var words: [String] = [shiftHandoff, location, customer, outOfStock]
        words.append(contentsOf: roles)
        words.append(contentsOf: equipment)
        words.append(contentsOf: slang)
        return words
    }
}

nonisolated enum IndustrySeed {

    static let all: [IndustryTemplate] = [
        restaurant, barPub, hotel, cafe, retail,
        healthcare, manufacturing, security,
        propertyManagement, construction, other
    ]

    // MARK: - Hospitality

    static let restaurant = IndustryTemplate(
        id: "restaurant",
        name: "Restaurant",
        icon: "fork.knife",
        defaultCategories: [
            CategoryTemplate(id: "cat_kitchen", name: "Kitchen", icon: "fork.knife", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_foh", name: "FOH", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_inventory", name: "Inventory", icon: "shippingbox.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_maint", name: "Maintenance", icon: "hammer.fill", colorHex: "#EA580C"),
            CategoryTemplate(id: "cat_staff", name: "Staff", icon: "person.crop.circle.badge.checkmark", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_hs", name: "Health & Safety", icon: "cross.circle.fill", colorHex: "#DC2626"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_open", name: "Opening", icon: "sunrise.fill", defaultStartHour: 6),
            ShiftTemplate(id: "shift_mid", name: "Mid", icon: "sun.max.fill", defaultStartHour: 11),
            ShiftTemplate(id: "shift_close", name: "Closing", icon: "moon.stars.fill", defaultStartHour: 16),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_owner", name: "Owner", sortOrder: 0),
            RoleTemplate(id: "role_gm", name: "General Manager", sortOrder: 1),
            RoleTemplate(id: "role_mgr", name: "Manager", sortOrder: 2),
            RoleTemplate(id: "role_lead", name: "Shift Lead", sortOrder: 3),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Handoff",
            location: "Location",
            customer: "Guest",
            outOfStock: "86'd",
            roles: [
                "barback", "barbacks", "busser", "bussers", "food runner", "food runners",
                "expo", "expeditor", "line cook", "line cooks", "prep cook", "prep cooks",
                "sous chef", "executive chef", "chef de partie", "saucier", "garde manger",
                "pastry chef", "dishwasher", "host", "hostess", "server", "servers",
                "bartender", "bartenders", "sommelier", "maitre d", "FOH manager",
                "BOH manager", "general manager", "GM", "shift lead", "closer", "opener"
            ],
            equipment: [
                "walk-in", "walk-in cooler", "walk-in freezer", "lowboy", "reach-in",
                "flat top", "flat-top grill", "char grill", "salamander", "broiler",
                "fryer", "deep fryer", "speed rack", "sheet pan", "hotel pan",
                "cambro", "Cambro", "bain-marie", "steam table", "sauté station",
                "POS", "POS system", "KDS", "kitchen display", "ticket printer",
                "ice machine", "dishpit", "dish pit", "three-compartment sink",
                "hood vent", "hood system", "grease trap", "dumbwaiter",
                "soda gun", "draft system", "keg", "kegs", "tap", "taps"
            ],
            slang: [
                "86", "86'd", "eighty-six", "eighty-sixed", "in the weeds", "weeded",
                "behind", "heard", "corner", "hot behind", "sharp",
                "on the fly", "fire", "all day", "mise en place", "mise",
                "two-top", "four-top", "deuce", "turn and burn",
                "comp", "comped", "comp'd", "void", "no-show",
                "FOH", "BOH", "front of house", "back of house",
                "side work", "sidework", "pre-shift", "rollup", "roll-up",
                "cut", "cut list", "on the line", "the pass", "window",
                "rail", "well", "top shelf", "call", "neat", "rocks",
                "happy hour", "last call", "closing duties", "opening duties"
            ]
        )
    )

    static let barPub = IndustryTemplate(
        id: "bar_pub",
        name: "Bar / Pub",
        icon: "wineglass.fill",
        defaultCategories: [
            CategoryTemplate(id: "cat_86", name: "86'd Items", icon: "xmark.circle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_equip", name: "Equipment", icon: "wrench.and.screwdriver.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_guest", name: "Guest Issues", icon: "person.crop.circle.badge.exclamationmark.fill", colorHex: "#BE185D"),
            CategoryTemplate(id: "cat_staff", name: "Staff Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_inv", name: "Inventory", icon: "shippingbox.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_maint", name: "Maintenance", icon: "hammer.fill", colorHex: "#EA580C"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_open", name: "Opening", icon: "sunrise.fill", defaultStartHour: 10),
            ShiftTemplate(id: "shift_mid", name: "Mid", icon: "sun.max.fill", defaultStartHour: 16),
            ShiftTemplate(id: "shift_close", name: "Closing", icon: "moon.stars.fill", defaultStartHour: 23),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_owner", name: "Owner", sortOrder: 0),
            RoleTemplate(id: "role_gm", name: "General Manager", sortOrder: 1),
            RoleTemplate(id: "role_mgr", name: "Bar Manager", sortOrder: 2),
            RoleTemplate(id: "role_lead", name: "Shift Lead", sortOrder: 3),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Handoff",
            location: "Location",
            customer: "Guest",
            outOfStock: "86'd",
            roles: [
                "barback", "barbacks", "bartender", "bartenders", "bouncer", "bouncers",
                "door guy", "doorman", "server", "servers", "cocktail server",
                "bar manager", "floor manager", "GM", "general manager",
                "busser", "bussers", "promoter", "promoters",
                "DJ", "sound tech", "security", "shift lead"
            ],
            equipment: [
                "speed rail", "speed rack", "well", "ice well", "bar mat",
                "jigger", "shaker", "mixing glass", "strainer", "muddler",
                "POS", "POS system", "tab", "tabs", "keg", "kegs",
                "draft system", "tap", "taps", "beer tower", "glycol system",
                "glass washer", "ice machine", "cooler", "reach-in",
                "soda gun", "CO2 tank", "nitrogen tank", "infusion jar"
            ],
            slang: [
                "86", "86'd", "eighty-six", "eighty-sixed", "last call",
                "cut off", "over-served", "comp", "comped", "comp'd",
                "tab", "close out", "walk out", "dine and dash",
                "well drink", "call", "top shelf", "neat", "rocks", "up",
                "back", "on the rocks", "happy hour", "two-for-one",
                "FOH", "BOH", "front of house", "back of house",
                "closing duties", "opening duties", "pre-shift",
                "the rail", "the stick", "behind the stick"
            ]
        )
    )

    static let hotel = IndustryTemplate(
        id: "hotel",
        name: "Hotel",
        icon: "building.2.fill",
        defaultCategories: [
            CategoryTemplate(id: "cat_guest", name: "Guest Issues", icon: "person.crop.circle.badge.exclamationmark.fill", colorHex: "#BE185D"),
            CategoryTemplate(id: "cat_reso", name: "Reservations/VIP", icon: "star.fill", colorHex: "#7C3AED"),
            CategoryTemplate(id: "cat_staff", name: "Staff Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_maint", name: "Maintenance", icon: "hammer.fill", colorHex: "#EA580C"),
            CategoryTemplate(id: "cat_hs", name: "Health & Safety", icon: "cross.circle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_inv", name: "Inventory", icon: "shippingbox.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_day", name: "Day", icon: "sun.max.fill", defaultStartHour: 7),
            ShiftTemplate(id: "shift_eve", name: "Evening", icon: "sunset.fill", defaultStartHour: 15),
            ShiftTemplate(id: "shift_night", name: "Night", icon: "moon.stars.fill", defaultStartHour: 23),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_owner", name: "Owner", sortOrder: 0),
            RoleTemplate(id: "role_gm", name: "General Manager", sortOrder: 1),
            RoleTemplate(id: "role_fom", name: "Front Office Manager", sortOrder: 2),
            RoleTemplate(id: "role_lead", name: "Shift Lead", sortOrder: 3),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Handoff",
            location: "Property",
            customer: "Guest",
            outOfStock: "Out of Stock",
            roles: [
                "front desk agent", "front desk", "FDA", "concierge",
                "bellman", "bellhop", "valet", "housekeeper", "housekeeping",
                "room attendant", "laundry attendant", "night auditor",
                "FOM", "front office manager", "revenue manager",
                "banquet captain", "banquet server", "engineer",
                "maintenance tech", "GM", "AGM", "MOD", "manager on duty"
            ],
            equipment: [
                "PMS", "property management system", "key encoder", "key card",
                "HVAC", "boiler", "chiller", "laundry press", "industrial washer",
                "POS", "minibar", "safe", "in-room safe",
                "luggage cart", "bellman cart", "housekeeping cart",
                "linen closet", "supply closet"
            ],
            slang: [
                "OOO", "out of order", "DND", "do not disturb",
                "VIP", "VVIP", "walk", "walked a guest", "no-show",
                "OTA", "over-the-air", "rack rate", "ADR", "RevPAR",
                "comp", "comped", "upgrade", "upsell",
                "turndown", "turn down", "stayover", "checkout",
                "late checkout", "early check-in", "due out",
                "house count", "occupancy"
            ]
        )
    )

    static let cafe = IndustryTemplate(
        id: "cafe",
        name: "Café",
        icon: "cup.and.saucer.fill",
        defaultCategories: [
            CategoryTemplate(id: "cat_86", name: "86'd Items", icon: "xmark.circle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_equip", name: "Equipment", icon: "wrench.and.screwdriver.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_staff", name: "Staff Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_inv", name: "Inventory", icon: "shippingbox.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_hs", name: "Health & Safety", icon: "cross.circle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_open", name: "Opening", icon: "sunrise.fill", defaultStartHour: 5),
            ShiftTemplate(id: "shift_mid", name: "Mid", icon: "sun.max.fill", defaultStartHour: 11),
            ShiftTemplate(id: "shift_close", name: "Closing", icon: "moon.stars.fill", defaultStartHour: 17),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_owner", name: "Owner", sortOrder: 0),
            RoleTemplate(id: "role_mgr", name: "Manager", sortOrder: 1),
            RoleTemplate(id: "role_lead", name: "Shift Lead", sortOrder: 2),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Handoff",
            location: "Location",
            customer: "Customer",
            outOfStock: "86'd",
            roles: [
                "barista", "baristas", "shift lead", "shift supervisor",
                "opener", "closer", "mid", "trainer"
            ],
            equipment: [
                "espresso machine", "portafilter", "grinder", "burr grinder",
                "steam wand", "knock box", "drip brewer", "pour over",
                "cold brew tower", "nitro tap", "blender", "POS",
                "pastry case", "reach-in", "undercounter fridge"
            ],
            slang: [
                "86", "86'd", "pull a shot", "dial in", "dialed in",
                "latte art", "flat white", "cortado", "americano",
                "ristretto", "doppio", "red eye", "drip",
                "pre-shift", "closing duties", "opening duties",
                "FOH", "BOH"
            ]
        )
    )

    static let retail = IndustryTemplate(
        id: "retail",
        name: "Retail",
        icon: "bag.fill",
        defaultCategories: [
            CategoryTemplate(id: "cat_staff", name: "Staff Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_inv", name: "Inventory", icon: "shippingbox.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_maint", name: "Maintenance", icon: "hammer.fill", colorHex: "#EA580C"),
            CategoryTemplate(id: "cat_cust", name: "Customer Issues", icon: "person.crop.circle.badge.exclamationmark.fill", colorHex: "#BE185D"),
            CategoryTemplate(id: "cat_loss", name: "Loss Prevention", icon: "exclamationmark.shield.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_open", name: "Opening", icon: "sunrise.fill", defaultStartHour: 8),
            ShiftTemplate(id: "shift_mid", name: "Mid", icon: "sun.max.fill", defaultStartHour: 13),
            ShiftTemplate(id: "shift_close", name: "Closing", icon: "moon.stars.fill", defaultStartHour: 18),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_owner", name: "Owner", sortOrder: 0),
            RoleTemplate(id: "role_sm", name: "Store Manager", sortOrder: 1),
            RoleTemplate(id: "role_asm", name: "Assistant Manager", sortOrder: 2),
            RoleTemplate(id: "role_lead", name: "Shift Lead", sortOrder: 3),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Handoff",
            location: "Store",
            customer: "Customer",
            outOfStock: "Out of Stock",
            roles: [
                "associate", "sales associate", "cashier", "stocker",
                "merchandiser", "visual merchandiser", "loss prevention",
                "LP", "key holder", "key-holder", "ASM", "assistant manager",
                "store manager", "SM", "DM", "district manager",
                "department lead", "team lead"
            ],
            equipment: [
                "POS", "register", "scanner", "handheld", "RF gun",
                "price gun", "security tag", "EAS", "fitting room",
                "stockroom", "back room", "pallet jack", "u-boat",
                "gondola", "endcap", "planogram"
            ],
            slang: [
                "shrink", "shrinkage", "facing", "fronting", "zoning",
                "recovery", "go-back", "go-backs", "return to floor",
                "markdown", "mark down", "BOGO", "SKU",
                "opening duties", "closing duties", "cash wrap",
                "fitting room", "LP", "code Adam"
            ]
        )
    )

    // MARK: - Healthcare

    static let healthcare = IndustryTemplate(
        id: "healthcare",
        name: "Healthcare / Nursing",
        icon: "stethoscope",
        defaultCategories: [
            CategoryTemplate(id: "cat_patient", name: "Patient Handoff", icon: "heart.text.clipboard.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_med", name: "Medication", icon: "pills.fill", colorHex: "#7C3AED"),
            CategoryTemplate(id: "cat_equip", name: "Equipment", icon: "wrench.and.screwdriver.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_incident", name: "Incident Report", icon: "exclamationmark.shield.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_staff", name: "Staff Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_supply", name: "Supplies", icon: "shippingbox.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_safety", name: "Safety / Compliance", icon: "cross.circle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_day", name: "Day", icon: "sun.max.fill", defaultStartHour: 7),
            ShiftTemplate(id: "shift_night", name: "Night", icon: "moon.stars.fill", defaultStartHour: 19),
            ShiftTemplate(id: "shift_overnight", name: "Overnight", icon: "moon.zzz.fill", defaultStartHour: 23),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_dir", name: "Director of Nursing", sortOrder: 0),
            RoleTemplate(id: "role_charge", name: "Charge Nurse", sortOrder: 1),
            RoleTemplate(id: "role_rn", name: "Registered Nurse", sortOrder: 2),
            RoleTemplate(id: "role_cna", name: "CNA", sortOrder: 3),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Report",
            location: "Unit",
            customer: "Patient",
            outOfStock: "Out of Stock",
            roles: [
                "RN", "registered nurse", "LPN", "LVN", "CNA",
                "charge nurse", "nurse practitioner", "NP", "PA",
                "physician assistant", "attending", "resident",
                "med tech", "phlebotomist", "respiratory therapist", "RT",
                "unit secretary", "unit clerk", "house supervisor",
                "DON", "director of nursing", "ADON"
            ],
            equipment: [
                "IV pump", "infusion pump", "crash cart", "code cart",
                "vitals monitor", "pulse ox", "BP cuff", "glucometer",
                "Hoyer lift", "Hoyer", "gait belt", "wheelchair",
                "bed alarm", "call light", "suction", "O2", "oxygen",
                "nasal cannula", "ventilator", "vent", "EHR", "MAR"
            ],
            slang: [
                "SBAR", "handoff", "bedside report", "chart", "charting",
                "admit", "discharge", "transfer", "D/C",
                "PRN", "as needed", "stat", "STAT",
                "code blue", "rapid response", "fall risk",
                "isolation", "precautions", "contact precautions",
                "skin check", "turn and reposition", "I&O",
                "med pass", "medication pass", "vitals"
            ]
        )
    )

    // MARK: - Manufacturing

    static let manufacturing = IndustryTemplate(
        id: "manufacturing",
        name: "Manufacturing / Warehouse",
        icon: "gearshape.2.fill",
        defaultCategories: [
            CategoryTemplate(id: "cat_equip", name: "Equipment / Machine", icon: "gearshape.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_safety", name: "Safety Incident", icon: "exclamationmark.triangle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_quality", name: "Quality Issue", icon: "checkmark.seal.fill", colorHex: "#7C3AED"),
            CategoryTemplate(id: "cat_maint", name: "Maintenance", icon: "hammer.fill", colorHex: "#EA580C"),
            CategoryTemplate(id: "cat_inv", name: "Inventory / Materials", icon: "shippingbox.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_staff", name: "Staff Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_prod", name: "Production Update", icon: "chart.bar.fill", colorHex: "#16A34A"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_day", name: "Day", icon: "sun.max.fill", defaultStartHour: 6),
            ShiftTemplate(id: "shift_swing", name: "Swing", icon: "sunset.fill", defaultStartHour: 14),
            ShiftTemplate(id: "shift_night", name: "Night", icon: "moon.stars.fill", defaultStartHour: 22),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_pm", name: "Plant Manager", sortOrder: 0),
            RoleTemplate(id: "role_sup", name: "Supervisor", sortOrder: 1),
            RoleTemplate(id: "role_lead", name: "Team Lead", sortOrder: 2),
            RoleTemplate(id: "role_op", name: "Operator", sortOrder: 3),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Handover",
            location: "Facility",
            customer: "Client",
            outOfStock: "Out of Stock",
            roles: [
                "operator", "machine operator", "forklift operator",
                "forklift driver", "picker", "packer", "loader",
                "quality inspector", "QA", "QC", "maintenance tech",
                "team lead", "supervisor", "plant manager",
                "line lead", "shipping clerk", "receiving clerk"
            ],
            equipment: [
                "forklift", "pallet jack", "conveyor", "conveyor belt",
                "CNC", "CNC machine", "press", "stamping press",
                "injection mold", "compressor", "air compressor",
                "overhead crane", "hoist", "dock leveler",
                "shrink wrapper", "bander", "label printer",
                "ERP", "WMS", "warehouse management system"
            ],
            slang: [
                "downtime", "changeover", "setup", "teardown",
                "scrap", "rework", "reject", "first article",
                "FIFO", "LIFO", "cycle count", "pick list",
                "BOL", "bill of lading", "ASN",
                "lockout tagout", "LOTO", "PPE",
                "near miss", "incident report", "safety stand-down"
            ]
        )
    )

    // MARK: - Security

    static let security = IndustryTemplate(
        id: "security",
        name: "Security / Facilities",
        icon: "shield.checkered",
        defaultCategories: [
            CategoryTemplate(id: "cat_incident", name: "Incident Report", icon: "exclamationmark.shield.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_access", name: "Access / Entry", icon: "lock.shield.fill", colorHex: "#7C3AED"),
            CategoryTemplate(id: "cat_patrol", name: "Patrol Notes", icon: "figure.walk", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_equip", name: "Equipment", icon: "wrench.and.screwdriver.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_maint", name: "Maintenance", icon: "hammer.fill", colorHex: "#EA580C"),
            CategoryTemplate(id: "cat_staff", name: "Staff Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_safety", name: "Health & Safety", icon: "cross.circle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_day", name: "Day", icon: "sun.max.fill", defaultStartHour: 6),
            ShiftTemplate(id: "shift_swing", name: "Swing", icon: "sunset.fill", defaultStartHour: 14),
            ShiftTemplate(id: "shift_night", name: "Night", icon: "moon.stars.fill", defaultStartHour: 22),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_dir", name: "Security Director", sortOrder: 0),
            RoleTemplate(id: "role_sup", name: "Supervisor", sortOrder: 1),
            RoleTemplate(id: "role_lead", name: "Shift Lead", sortOrder: 2),
            RoleTemplate(id: "role_officer", name: "Officer", sortOrder: 3),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Briefing",
            location: "Site",
            customer: "Client",
            outOfStock: "Out of Stock",
            roles: [
                "officer", "guard", "patrol officer", "dispatcher",
                "post commander", "site supervisor", "rover",
                "access control", "CCTV operator", "control room"
            ],
            equipment: [
                "CCTV", "camera", "DVR", "NVR", "access panel",
                "key card reader", "radio", "two-way radio", "walkie",
                "body cam", "flashlight", "patrol vehicle",
                "gate arm", "bollard", "turnstile"
            ],
            slang: [
                "patrol", "rounds", "post", "relief",
                "incident report", "IR", "trespass", "trespasser",
                "all clear", "10-4", "copy", "standby",
                "escort", "lockdown", "sweep", "perimeter check"
            ]
        )
    )

    // MARK: - Property Management

    static let propertyManagement = IndustryTemplate(
        id: "property_management",
        name: "Property Management",
        icon: "house.and.flag.fill",
        defaultCategories: [
            CategoryTemplate(id: "cat_tenant", name: "Tenant Issues", icon: "person.crop.circle.badge.exclamationmark.fill", colorHex: "#BE185D"),
            CategoryTemplate(id: "cat_maint", name: "Maintenance", icon: "hammer.fill", colorHex: "#EA580C"),
            CategoryTemplate(id: "cat_inspect", name: "Inspection", icon: "checklist", colorHex: "#7C3AED"),
            CategoryTemplate(id: "cat_equip", name: "Equipment", icon: "wrench.and.screwdriver.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_safety", name: "Health & Safety", icon: "cross.circle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_staff", name: "Staff Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_vendor", name: "Vendor / Contractor", icon: "person.badge.key.fill", colorHex: "#16A34A"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_morning", name: "Morning", icon: "sunrise.fill", defaultStartHour: 7),
            ShiftTemplate(id: "shift_afternoon", name: "Afternoon", icon: "sun.max.fill", defaultStartHour: 13),
            ShiftTemplate(id: "shift_evening", name: "Evening", icon: "moon.stars.fill", defaultStartHour: 19),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_owner", name: "Property Owner", sortOrder: 0),
            RoleTemplate(id: "role_pm", name: "Property Manager", sortOrder: 1),
            RoleTemplate(id: "role_am", name: "Assistant Manager", sortOrder: 2),
            RoleTemplate(id: "role_maint", name: "Maintenance Lead", sortOrder: 3),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Handoff",
            location: "Property",
            customer: "Tenant",
            outOfStock: "Out of Stock",
            roles: [
                "property manager", "PM", "assistant manager",
                "leasing agent", "leasing consultant", "maintenance tech",
                "maintenance supervisor", "porter", "concierge",
                "groundskeeper", "super", "superintendent"
            ],
            equipment: [
                "HVAC", "boiler", "chiller", "elevator", "compactor",
                "key fob", "intercom", "fire panel", "sprinkler system",
                "sump pump", "generator", "backflow preventer"
            ],
            slang: [
                "work order", "service request", "lease", "renewal",
                "move-in", "move-out", "turnover", "unit turn",
                "vacancy", "occupied", "delinquent", "eviction",
                "HOA", "common area", "amenity", "punch list"
            ]
        )
    )

    // MARK: - Construction

    static let construction = IndustryTemplate(
        id: "construction",
        name: "Construction",
        icon: "hammer.fill",
        defaultCategories: [
            CategoryTemplate(id: "cat_safety", name: "Safety Incident", icon: "exclamationmark.triangle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_equip", name: "Equipment", icon: "wrench.and.screwdriver.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_material", name: "Materials / Deliveries", icon: "shippingbox.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_progress", name: "Progress Update", icon: "chart.bar.fill", colorHex: "#16A34A"),
            CategoryTemplate(id: "cat_weather", name: "Weather Delay", icon: "cloud.rain.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_inspect", name: "Inspection", icon: "checklist", colorHex: "#7C3AED"),
            CategoryTemplate(id: "cat_staff", name: "Crew Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_day", name: "Day", icon: "sun.max.fill", defaultStartHour: 6),
            ShiftTemplate(id: "shift_night", name: "Night", icon: "moon.stars.fill", defaultStartHour: 18),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_pm", name: "Project Manager", sortOrder: 0),
            RoleTemplate(id: "role_super", name: "Superintendent", sortOrder: 1),
            RoleTemplate(id: "role_foreman", name: "Foreman", sortOrder: 2),
            RoleTemplate(id: "role_lead", name: "Crew Lead", sortOrder: 3),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Report",
            location: "Job Site",
            customer: "Client",
            outOfStock: "Out of Stock",
            roles: [
                "foreman", "superintendent", "project manager",
                "journeyman", "apprentice", "laborer", "operator",
                "crane operator", "electrician", "plumber", "pipefitter",
                "ironworker", "carpenter", "mason", "welder",
                "safety officer", "inspector", "subcontractor", "sub"
            ],
            equipment: [
                "excavator", "backhoe", "loader", "skid steer", "Bobcat",
                "crane", "boom lift", "scissor lift", "scaffold",
                "jackhammer", "concrete pump", "mixer", "rebar",
                "generator", "compressor", "laser level", "total station",
                "dump truck", "flatbed"
            ],
            slang: [
                "RFI", "request for information", "change order", "CO",
                "punch list", "punch", "substantial completion",
                "mobilize", "demobilize", "pour", "concrete pour",
                "formwork", "grade", "grading", "backfill",
                "OSHA", "toolbox talk", "safety stand-down",
                "PPE", "hard hat", "hi-vis"
            ]
        )
    )

    // MARK: - Other

    static let other = IndustryTemplate(
        id: "other",
        name: "Other",
        icon: "square.grid.2x2.fill",
        defaultCategories: [
            CategoryTemplate(id: "cat_staff", name: "Staff Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_equip", name: "Equipment", icon: "wrench.and.screwdriver.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_maint", name: "Maintenance", icon: "hammer.fill", colorHex: "#EA580C"),
            CategoryTemplate(id: "cat_incident", name: "Incident Report", icon: "exclamationmark.shield.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_morning", name: "Morning", icon: "sunrise.fill", defaultStartHour: 6),
            ShiftTemplate(id: "shift_afternoon", name: "Afternoon", icon: "sun.max.fill", defaultStartHour: 14),
            ShiftTemplate(id: "shift_evening", name: "Evening", icon: "moon.stars.fill", defaultStartHour: 22),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_owner", name: "Owner", sortOrder: 0),
            RoleTemplate(id: "role_mgr", name: "Manager", sortOrder: 1),
            RoleTemplate(id: "role_lead", name: "Shift Lead", sortOrder: 2),
        ],
        terminology: IndustryTerminology(
            shiftHandoff: "Shift Handoff",
            location: "Location",
            customer: "Customer",
            outOfStock: "Out of Stock"
        )
    )

    static func template(for businessType: BusinessType) -> IndustryTemplate {
        switch businessType {
        case .restaurant: return restaurant
        case .barPub: return barPub
        case .hotel: return hotel
        case .cafe: return cafe
        case .retail: return retail
        case .healthcare: return healthcare
        case .manufacturing: return manufacturing
        case .security: return security
        case .propertyManagement: return propertyManagement
        case .construction: return construction
        case .other: return other
        }
    }

    static func template(forId id: String) -> IndustryTemplate? {
        all.first { $0.id == id }
    }
}
