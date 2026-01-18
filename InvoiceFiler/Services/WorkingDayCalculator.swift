import Foundation

/// Calculates working days accounting for weekends and bank holidays
final class WorkingDayCalculator {

    // MARK: - Singleton

    static let shared = WorkingDayCalculator()

    // MARK: - Properties

    private let bankHolidayService = BankHolidayService.shared
    private let calendar: Calendar

    // MARK: - Initialization

    private init() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // Monday = 1 in some locales, 2 in others
        self.calendar = cal
    }

    // MARK: - Public API

    /// Calculate the date that is N working days before a target date
    /// - Parameters:
    ///   - workingDays: Number of working days to subtract
    ///   - targetDate: The target date (e.g., invoice due date)
    ///   - senderCountry: ISO country code for sender's bank holidays
    ///   - recipientCountry: ISO country code for recipient's bank holidays
    ///   - completion: Completion handler with calculated date or error
    func dateSubtractingWorkingDays(
        _ workingDays: Int,
        from targetDate: Date,
        senderCountry: String,
        recipientCountry: String,
        completion: @escaping (Result<Date, Error>) -> Void
    ) {
        let year = calendar.component(.year, from: targetDate)
        let previousYear = year - 1  // In case we cross year boundary

        // Fetch holidays for both countries and both years
        let group = DispatchGroup()
        var senderHolidays: Set<String> = []
        var recipientHolidays: Set<String> = []
        var fetchError: Error?

        // Fetch sender holidays
        for y in [previousYear, year] {
            group.enter()
            bankHolidayService.fetchHolidays(countryCode: senderCountry, year: y) { result in
                switch result {
                case .success(let holidays):
                    senderHolidays.formUnion(holidays.map { $0.date })
                case .failure(let error):
                    if fetchError == nil { fetchError = error }
                }
                group.leave()
            }
        }

        // Fetch recipient holidays
        for y in [previousYear, year] {
            group.enter()
            bankHolidayService.fetchHolidays(countryCode: recipientCountry, year: y) { result in
                switch result {
                case .success(let holidays):
                    recipientHolidays.formUnion(holidays.map { $0.date })
                case .failure(let error):
                    if fetchError == nil { fetchError = error }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else {
                completion(.failure(WorkingDayError.calculatorDeallocated))
                return
            }

            if let error = fetchError {
                completion(.failure(error))
                return
            }

            // Combine holidays from both countries
            let allHolidays = senderHolidays.union(recipientHolidays)

            // Calculate the date
            let result = self.subtractWorkingDays(
                workingDays,
                from: targetDate,
                holidays: allHolidays
            )

            completion(.success(result))
        }
    }

    /// Calculate the date that is N working days after a start date
    /// - Parameters:
    ///   - workingDays: Number of working days to add
    ///   - startDate: The start date
    ///   - senderCountry: ISO country code for sender's bank holidays
    ///   - recipientCountry: ISO country code for recipient's bank holidays
    ///   - completion: Completion handler with calculated date or error
    func dateAddingWorkingDays(
        _ workingDays: Int,
        from startDate: Date,
        senderCountry: String,
        recipientCountry: String,
        completion: @escaping (Result<Date, Error>) -> Void
    ) {
        let year = calendar.component(.year, from: startDate)
        let nextYear = year + 1

        let group = DispatchGroup()
        var senderHolidays: Set<String> = []
        var recipientHolidays: Set<String> = []
        var fetchError: Error?

        for y in [year, nextYear] {
            group.enter()
            bankHolidayService.fetchHolidays(countryCode: senderCountry, year: y) { result in
                switch result {
                case .success(let holidays):
                    senderHolidays.formUnion(holidays.map { $0.date })
                case .failure(let error):
                    if fetchError == nil { fetchError = error }
                }
                group.leave()
            }

            group.enter()
            bankHolidayService.fetchHolidays(countryCode: recipientCountry, year: y) { result in
                switch result {
                case .success(let holidays):
                    recipientHolidays.formUnion(holidays.map { $0.date })
                case .failure(let error):
                    if fetchError == nil { fetchError = error }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else {
                completion(.failure(WorkingDayError.calculatorDeallocated))
                return
            }

            if let error = fetchError {
                completion(.failure(error))
                return
            }

            let allHolidays = senderHolidays.union(recipientHolidays)
            let result = self.addWorkingDays(workingDays, from: startDate, holidays: allHolidays)
            completion(.success(result))
        }
    }

    /// Check if a date is a working day
    /// - Parameters:
    ///   - date: The date to check
    ///   - senderCountry: ISO country code for sender
    ///   - recipientCountry: ISO country code for recipient
    ///   - completion: Completion handler with boolean result
    func isWorkingDay(
        date: Date,
        senderCountry: String,
        recipientCountry: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        // Check weekend first
        if isWeekend(date) {
            completion(.success(false))
            return
        }

        let year = calendar.component(.year, from: date)
        let dateString = formatDate(date)

        let group = DispatchGroup()
        var isHoliday = false
        var fetchError: Error?

        group.enter()
        bankHolidayService.fetchHolidays(countryCode: senderCountry, year: year) { result in
            switch result {
            case .success(let holidays):
                if holidays.contains(where: { $0.date == dateString }) {
                    isHoliday = true
                }
            case .failure(let error):
                if fetchError == nil { fetchError = error }
            }
            group.leave()
        }

        group.enter()
        bankHolidayService.fetchHolidays(countryCode: recipientCountry, year: year) { result in
            switch result {
            case .success(let holidays):
                if holidays.contains(where: { $0.date == dateString }) {
                    isHoliday = true
                }
            case .failure(let error):
                if fetchError == nil { fetchError = error }
            }
            group.leave()
        }

        group.notify(queue: .main) {
            if let error = fetchError {
                completion(.failure(error))
            } else {
                completion(.success(!isHoliday))
            }
        }
    }

    /// Get the next working day on or after the given date
    func nextWorkingDay(
        from date: Date,
        senderCountry: String,
        recipientCountry: String,
        completion: @escaping (Result<Date, Error>) -> Void
    ) {
        isWorkingDay(date: date, senderCountry: senderCountry, recipientCountry: recipientCountry) { [weak self] result in
            switch result {
            case .success(let isWorking):
                if isWorking {
                    completion(.success(date))
                } else {
                    guard let self = self,
                          let nextDay = self.calendar.date(byAdding: .day, value: 1, to: date) else {
                        completion(.failure(WorkingDayError.calculatorDeallocated))
                        return
                    }
                    self.nextWorkingDay(
                        from: nextDay,
                        senderCountry: senderCountry,
                        recipientCountry: recipientCountry,
                        completion: completion
                    )
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Get the previous working day on or before the given date
    /// If the given date is a working day, returns it. Otherwise, returns the most recent prior working day.
    func previousWorkingDayOnOrBefore(
        date: Date,
        senderCountry: String,
        recipientCountry: String,
        completion: @escaping (Result<Date, Error>) -> Void
    ) {
        isWorkingDay(date: date, senderCountry: senderCountry, recipientCountry: recipientCountry) { [weak self] result in
            switch result {
            case .success(let isWorking):
                if isWorking {
                    completion(.success(date))
                } else {
                    guard let self = self,
                          let previousDay = self.calendar.date(byAdding: .day, value: -1, to: date) else {
                        completion(.failure(WorkingDayError.calculatorDeallocated))
                        return
                    }
                    self.previousWorkingDayOnOrBefore(
                        date: previousDay,
                        senderCountry: senderCountry,
                        recipientCountry: recipientCountry,
                        completion: completion
                    )
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Private Methods

    private func isWeekend(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        // Sunday = 1, Saturday = 7
        return weekday == 1 || weekday == 7
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func subtractWorkingDays(_ days: Int, from date: Date, holidays: Set<String>) -> Date {
        var currentDate = date
        var remainingDays = days

        while remainingDays > 0 {
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate

            if !isWeekend(currentDate) && !holidays.contains(formatDate(currentDate)) {
                remainingDays -= 1
            }
        }

        return currentDate
    }

    private func addWorkingDays(_ days: Int, from date: Date, holidays: Set<String>) -> Date {
        var currentDate = date
        var remainingDays = days

        while remainingDays > 0 {
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate

            if !isWeekend(currentDate) && !holidays.contains(formatDate(currentDate)) {
                remainingDays -= 1
            }
        }

        return currentDate
    }
}

// MARK: - Errors

enum WorkingDayError: LocalizedError {
    case calculatorDeallocated

    var errorDescription: String? {
        switch self {
        case .calculatorDeallocated:
            return "Working day calculator was deallocated during calculation"
        }
    }
}
