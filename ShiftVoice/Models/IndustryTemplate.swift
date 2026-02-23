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

    init(shiftHandoff: String = "Shift Handoff", location: String = "Location", customer: String = "Customer", outOfStock: String = "Out of Stock") {
        self.shiftHandoff = shiftHandoff
        self.location = location
        self.customer = customer
        self.outOfStock = outOfStock
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
            CategoryTemplate(id: "cat_86", name: "86'd Items", icon: "xmark.circle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_equip", name: "Equipment", icon: "wrench.and.screwdriver.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_guest", name: "Guest Issues", icon: "person.crop.circle.badge.exclamationmark.fill", colorHex: "#BE185D"),
            CategoryTemplate(id: "cat_reso", name: "Reservations/VIP", icon: "star.fill", colorHex: "#7C3AED"),
            CategoryTemplate(id: "cat_staff", name: "Staff Notes", icon: "person.2.fill", colorHex: "#2563EB"),
            CategoryTemplate(id: "cat_inv", name: "Inventory", icon: "shippingbox.fill", colorHex: "#D97706"),
            CategoryTemplate(id: "cat_hs", name: "Health & Safety", icon: "cross.circle.fill", colorHex: "#DC2626"),
            CategoryTemplate(id: "cat_gen", name: "General", icon: "doc.text.fill", colorHex: "#9CA3AF"),
        ],
        defaultShifts: [
            ShiftTemplate(id: "shift_open", name: "Opening", icon: "sunrise.fill", defaultStartHour: 6),
            ShiftTemplate(id: "shift_mid", name: "Mid", icon: "sun.max.fill", defaultStartHour: 14),
            ShiftTemplate(id: "shift_close", name: "Closing", icon: "moon.stars.fill", defaultStartHour: 22),
        ],
        defaultRoles: [
            RoleTemplate(id: "role_owner", name: "Owner", sortOrder: 0),
            RoleTemplate(id: "role_gm", name: "General Manager", sortOrder: 1),
            RoleTemplate(id: "role_mgr", name: "Manager", sortOrder: 2),
            RoleTemplate(id: "role_lead", name: "Shift Lead", sortOrder: 3),
        ],
        terminology: IndustryTerminology(shiftHandoff: "Shift Handoff", location: "Location", customer: "Guest", outOfStock: "86'd")
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
        terminology: IndustryTerminology(shiftHandoff: "Shift Handoff", location: "Location", customer: "Guest", outOfStock: "86'd")
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
        terminology: IndustryTerminology(shiftHandoff: "Shift Handoff", location: "Property", customer: "Guest", outOfStock: "Out of Stock")
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
        terminology: IndustryTerminology(shiftHandoff: "Shift Handoff", location: "Location", customer: "Customer", outOfStock: "86'd")
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
        terminology: IndustryTerminology(shiftHandoff: "Shift Handoff", location: "Store", customer: "Customer", outOfStock: "Out of Stock")
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
        terminology: IndustryTerminology(shiftHandoff: "Shift Report", location: "Unit", customer: "Patient", outOfStock: "Out of Stock")
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
        terminology: IndustryTerminology(shiftHandoff: "Shift Handover", location: "Facility", customer: "Client", outOfStock: "Out of Stock")
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
        terminology: IndustryTerminology(shiftHandoff: "Shift Briefing", location: "Site", customer: "Client", outOfStock: "Out of Stock")
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
        terminology: IndustryTerminology(shiftHandoff: "Shift Handoff", location: "Property", customer: "Tenant", outOfStock: "Out of Stock")
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
        terminology: IndustryTerminology(shiftHandoff: "Shift Report", location: "Job Site", customer: "Client", outOfStock: "Out of Stock")
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
        terminology: IndustryTerminology(shiftHandoff: "Shift Handoff", location: "Location", customer: "Customer", outOfStock: "Out of Stock")
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
