import UIKit
import HealthKit
import CoreMotion

enum HealthDate : Int {
    case today = 0
    case day = 1
    case week = 2
    case currentWeek = 3
    case month = 4
    case currentMonth = 5
    case year = 6
    case currentYear = 7
    case all = 8
    case yesterday = 9
}

// TOOD: - create singletone instead

class Health: NSObject {

    private static let oneDay : Double = {
        return 86400
    }()
    
    private static let calories : Double = {
        return 0.01983
    }()
    
    private static let healthStore: HKHealthStore? = {
        return HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }()
    
    private static let pedometer : CMPedometer = {
        return CMPedometer()
    }()
    
    static func healthKitInit(completion: @escaping(_ success : Bool) -> Void) {
        checkAuthorization(completion: { success in
            completion(success)
        })
    }
    
    fileprivate static func checkAuthorization(completion : @escaping(_ success : Bool) -> Void) {
        if healthStore == nil {
            completion(false)
            return
        }
        let permissionsRead : Set = [HKSampleType.quantityType(forIdentifier: .stepCount)!, HKSampleType.quantityType(forIdentifier: .distanceWalkingRunning)!, HKSampleType.quantityType(forIdentifier: .activeEnergyBurned)!, HKSampleType.quantityType(forIdentifier: .basalEnergyBurned)!, HKSampleType.quantityType(forIdentifier: .dietaryEnergyConsumed)!, HKSampleType.quantityType(forIdentifier: .height)!, HKSampleType.quantityType(forIdentifier: .bodyMass)!, HKSampleType.characteristicType(forIdentifier: .dateOfBirth)!, HKSampleType.characteristicType(forIdentifier: .biologicalSex)!]
        let permissionsShare : Set = [HKSampleType.quantityType(forIdentifier: .stepCount)!, HKSampleType.quantityType(forIdentifier: .distanceWalkingRunning)!, HKSampleType.quantityType(forIdentifier: .activeEnergyBurned)!, HKSampleType.quantityType(forIdentifier: .basalEnergyBurned)!, HKSampleType.quantityType(forIdentifier: .dietaryEnergyConsumed)!, HKSampleType.quantityType(forIdentifier: .height)!, HKSampleType.quantityType(forIdentifier: .bodyMass)!]
        healthStore?.requestAuthorization(toShare: permissionsShare, read: permissionsRead, completion: { (success, error) in
            if error == nil {
                completion(true)
            } else {
                print("Error: \(String(describing: error))")
            }
        })
    }
    
    static func currentData(completion: @escaping(Int, Double) -> Void) {
        getCurrentPedometerData(completion: { steps, distance in
            DispatchQueue.main.async {
                completion(Int(steps), distance)
            }
        })
    }
    
    static func getSteps(at hour: Int, completion: @escaping (Int) -> Void) {
        querySteps(at: hour, completion: { steps in
            DispatchQueue.main.async {
                completion(Int(steps))
            }
        })
    }
    
    static func requestSteps(for startDate : HealthDate, completion: @escaping([Int : Double]) -> Void) {
        var interval = DateComponents()
        interval.hour = 1
        request(type: .stepCount, startDate: startDate, interval: interval, completion: { values in
            completion(values)
        })
    }
    
    static func requestStepsForPeriod(startsFrom date : Date, completion : @escaping([[Date : Double]]) -> Void) {
        requestData(with: .stepCount, startDate: date, completion: { data in
            let keys = Array(data.keys).sorted()
            var steps : [[Date : Double]] = []
            for key in keys {
                steps.append([key : data[key] ?? 0])
            }
            completion(steps)
        })
    }
    
    static func allStepStatistic(for startDate : HealthDate, completion: @escaping([Date : Int]) -> Void) {
        var interval = DateComponents()
        interval.day = 1
        allStatistics(type: .stepCount, startDate: startDate, interval: interval, completion: { values in
            completion(values)
        })
    }
    
    static func requestStepsData(for startDate : HealthDate, completion: @escaping(Double) -> Void) {
        if startDate == .today {
            getTodaySteps(completion: { data in
                completion(data)
            })
        } else {
            sum(with: .stepCount, startDate: startDate, completion: { data in
                completion(data)
            })
        }
    }
    
    static func requestDistanceData(for startDate : HealthDate, completion: @escaping(Double) -> Void) {
        if startDate == .today {
            getTodayDistance(completion: { data in
                completion(data)
            })
        } else {
            sum(with: .distanceWalkingRunning, startDate: startDate, completion: { data in
                completion(data)
            })
        }
    }
    
    static func requestEnergyData(for startDate : HealthDate, completion: @escaping(Double) -> Void) {
        sum(with: .activeEnergyBurned, startDate: startDate, completion: { data in
            var data = data
            if data == 0 {
                let seconds = Int(fabs(Date().timeIntervalSince(date(to: startDate))))
                requestUserData(completion: { response in
                    let weight : Double = response["weight"] as? Double ?? 0.0
                    let height : Double = response["height"] as? Double ?? 0.0
                    let age : Int = response["age"] as? Int ?? 0
                    let sex : Int = response["sex"] as? Int ?? 0
                    if weight == 0 || height == 0 || age == 0 || sex == 0 {
                        data = calories
                    } else {
                        var dayCalories : Double = weight * 10 + 6.25 * height - Double(5 * age)
                        dayCalories = sex == 1 ? dayCalories + 5 : dayCalories - 161
                        data = dayCalories / 24 / 60 / 60
                    }
                    completion(data * Double(seconds))
                })
            } else {
                completion(data)
            }
        })
    }
    
    static func requestHeight(completion: @escaping(Double) -> Void) {
        recentSample(type: .height, completion: { data in
            DispatchQueue.main.async {
                completion(data)
            }
        })
    }
    
    static func requestWeight(completion: @escaping(Double) -> Void) {
        recentSample(type: .bodyMass, completion: { data in
            DispatchQueue.main.async {
                completion(data)
            }
        })
    }
    
    static func requestAge(completion: @escaping(Int) -> Void) {
        var age = 0
        if let birthDay = try? healthStore?.dateOfBirth() {
            age = Calendar.current.dateComponents([Calendar.Component.year], from: birthDay!, to: Date()).year ?? 0
        }
        DispatchQueue.main.async {
            completion(age)
        }
    }
    
    static func requestGender(completion: @escaping(Int) -> Void) {
        var sex = 0
        if let gender = try? healthStore?.biologicalSex() {
            sex = gender?.biologicalSex.rawValue ?? 0
        }
        DispatchQueue.main.async {
            completion(sex)
        }
    }
    
    private static func requestUserData(completion: @escaping([String : Any]) -> Void) {
        var data : [String : Any] = [:]
        requestHeight(completion: { height in
            data["height"] = height
            handler()
        })
        requestWeight(completion: { weight in
            data["weight"] = weight
            handler()
        })
        requestAge(completion: { age in
            data["age"] = age
            handler()
        })
        requestGender(completion: { sex in
            data["sex"] = sex
            handler()
        })
        func handler() {
            if data.count == 4 { completion(data) }
        }
    }
    
    static func share(height : Double) {
        saveSample(with: .height, value: height, startDate: Date())
    }
    
    static func share(weight : Double) {
        saveSample(with: .bodyMass, value: weight, startDate: Date())
    }
    
    static func share(steps : Double) {
        saveSample(with: .stepCount, value: steps, startDate: Date())
    }
    
    static func share(distance : Double) {
        saveSample(with: .distanceWalkingRunning, value: distance, startDate: Date())
    }
    
    static func share(kkal : Double) {
        saveSample(with: .activeEnergyBurned, value: kkal, startDate: Date())
    }
    
    static func shareCycling(distance : Double) {
        
    }
    
    fileprivate static func saveSample(with identifier: HKQuantityTypeIdentifier, value: Double, startDate : Date) {
        let type = HKSampleType.quantityType(forIdentifier: identifier)
        let quantity = HKQuantity(unit: unit(for: identifier.rawValue), doubleValue: value)
        let sample = HKQuantitySample(type: type!, quantity: quantity, start: startDate, end: Date())
        healthStore?.save(sample, withCompletion: { (success, error) in
            if error != nil {
                print(error!.localizedDescription)
            }
        })
    }
    
    fileprivate static func sum(with identifier: HKQuantityTypeIdentifier, startDate : HealthDate, completion: @escaping(_ data : Double) -> Void) {
        configureSourcePredicate(identifier: identifier, completion: { sourcePredicate in
            let type = HKSampleType.quantityType(forIdentifier: identifier)
            var predicate = HKQuery.predicateForSamples(withStart: date(to: startDate), end: Date(), options: [.strictStartDate, .strictEndDate])
            if sourcePredicate != nil {
                predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate , sourcePredicate!])
            }
            var interval : DateComponents = DateComponents()
            interval.day = 1
            let query = HKStatisticsCollectionQuery(quantityType: type!, quantitySamplePredicate: predicate, options: [.cumulativeSum], anchorDate: Date(), intervalComponents: interval)
            query.initialResultsHandler = { query, results, error in
                if error != nil || results == nil {
                    DispatchQueue.main.async {
                        completion(0)
                    }
                    return
                }
                var sum : Double = 0
                for stat in results!.statistics() {
                    sum += stat.sumQuantity()!.doubleValue(for: unit(for: identifier.rawValue))
                }
                DispatchQueue.main.async {
                    completion(sum)
                }
            }
            healthStore?.execute(query)
        })
    }
    
    fileprivate static func requestData(with identifier: HKQuantityTypeIdentifier, startDate: Date, completion: @escaping ([Date : Double]) -> Void) {
        configureSourcePredicate(identifier: identifier, completion: { sourcePredicate in
            let type = HKSampleType.quantityType(forIdentifier: identifier)
            var predicate = HKQuery.predicateForSamples(withStart: startDate, end: date(to: .yesterday), options: [.strictStartDate, .strictEndDate])
            if sourcePredicate != nil {
                predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate , sourcePredicate!])
            }
            var interval : DateComponents = DateComponents()
            interval.day = 1
            let query = HKStatisticsCollectionQuery(quantityType: type!, quantitySamplePredicate: predicate, options: [.cumulativeSum], anchorDate: date(to: .yesterday), intervalComponents: interval)
            query.initialResultsHandler = { query, results, error in
                if error != nil || results == nil {
                    DispatchQueue.main.async {
                        completion([:])
                    }
                    return
                }
                var data : [Date : Double] = [:]
                for stat in results!.statistics() {
                    data[stat.endDate.addingTimeInterval(-1)] = stat.sumQuantity()?.doubleValue(for: unit(for: identifier.rawValue))
                }
                DispatchQueue.main.async {
                    completion(data)
                }
            }
            healthStore?.execute(query)
        })
    }
    
    fileprivate static func request(type identifier: HKQuantityTypeIdentifier, startDate : HealthDate, interval : DateComponents, completion : @escaping(_ values : [Int : Double]) -> Void) {
        configureSourcePredicate(identifier: identifier, completion: { sourcePredicate in
            let type = HKSampleType.quantityType(forIdentifier: identifier)
            var predicate = HKQuery.predicateForSamples(withStart: date(to: startDate), end: Date(), options: [.strictStartDate, .strictEndDate])
            if sourcePredicate != nil {
                predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate , sourcePredicate!])
            }
            let query = HKStatisticsCollectionQuery(quantityType: type!, quantitySamplePredicate: predicate, options: [.cumulativeSum], anchorDate: Date(), intervalComponents: interval)
            query.initialResultsHandler = { query, results, error in
                var values : [Int : Double] = [:]
                for i in 0..<24 {
                    values[i] = 0
                }
                if error != nil || results == nil {
                    DispatchQueue.main.async { completion(values)}
                    return
                }
                for stat in results!.statistics() {
                    values[hour(date: stat.endDate)] = stat.sumQuantity()!.doubleValue(for: unit(for: identifier.rawValue))
                }
                DispatchQueue.main.async {
                    completion(values)
                }
            }
            healthStore?.execute(query)
        })
    }
    
    fileprivate static func allStatistics(type identifier: HKQuantityTypeIdentifier, startDate : HealthDate, interval : DateComponents, completion : @escaping(_ values : [Date : Int]) -> Void) {
        configureSourcePredicate(identifier: identifier, completion: { sourcePredicate in
            let type = HKSampleType.quantityType(forIdentifier: identifier)
            var predicate = HKQuery.predicateForSamples(withStart: date(to: startDate), end: nullEndDate, options: [.strictStartDate, .strictEndDate])
            if sourcePredicate != nil {
                predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate , sourcePredicate!])
            }
            let query = HKStatisticsCollectionQuery(quantityType: type!, quantitySamplePredicate: predicate, options: [.cumulativeSum], anchorDate: nullEndDate, intervalComponents: interval)
            query.initialResultsHandler = { query, results, error in
                if error != nil || results == nil {
                    DispatchQueue.main.async { completion([:]) }
                    return
                }
                var values : [Date : Int] = [:]
                for stat in results!.statistics() {
                    values[stat.startDate] = Int(stat.sumQuantity()!.doubleValue(for: unit(for: identifier.rawValue)))
                }
                DispatchQueue.main.async {
                    completion(values)
                }
            }
            healthStore?.execute(query)
        })
    }
    
    fileprivate static func recentSample(type identifier: HKQuantityTypeIdentifier, completion: @escaping(_ data : Double) -> Void) {
        configureSourcePredicate(identifier: identifier, completion: { sourcePredicate in
            let type = HKSampleType.quantityType(forIdentifier: identifier)
            var predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end:Date(), options: [.strictStartDate, .strictEndDate])
            if sourcePredicate != nil {
                predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate , sourcePredicate!])
            }
            let sortDescriptor = NSSortDescriptor(key:HKSampleSortIdentifierStartDate, ascending: false)
            let limit = 1
            let query = HKSampleQuery(sampleType: type!, predicate: predicate, limit: limit, sortDescriptors: [sortDescriptor])
            { query, results, error in
                if error != nil || results == nil {
                    completion(0)
                    return
                }
                if let sample = results!.first as? HKQuantitySample {
                    DispatchQueue.main.async {
                        completion(sample.quantity.doubleValue(for: unit(for: identifier.rawValue)))
                    }
                }
            }
            healthStore?.execute(query)
        })
    }
    
    fileprivate static func configureSourcePredicate(identifier: HKQuantityTypeIdentifier, completion: @escaping(NSPredicate?) -> Void) {
        var deviceSources : Set<HKSource> = Set()
        let appleHealth = "com.apple.health"
        let handler : (HKSourceQuery, Set<HKSource>?, Error?) -> Void = { query , sources , error in
            if sources == nil || error != nil {
                completion(nil)
                return
            }
            for source in sources! {
                if source.bundleIdentifier.hasPrefix(appleHealth){
                    deviceSources.insert(source)
                }
            }
            completion(HKQuery.predicateForObjects(from: deviceSources))
        }
        let sampleType = HKQuantityType.quantityType(forIdentifier: identifier)
        let sourceQuery = HKSourceQuery(sampleType: sampleType!, samplePredicate: nil, completionHandler: handler)
        healthStore?.execute(sourceQuery)
    }
    
    fileprivate static func hour(date : Date) -> Int {
        return Calendar.current.component(.hour, from: date)
    }
    
    fileprivate static func date(to startDate : HealthDate) -> Date {
        let date = Date()
        let calendar = Calendar.current
        switch startDate {
        case .today:
            return calendar.startOfDay(for: date)
        case .day: return date.addingTimeInterval(-oneDay)
        case .week: return date.addingTimeInterval(-oneDay * 7)
        case .currentWeek:
            var components = calendar.dateComponents([.weekday, .day, .month, .year], from: date)
            components.weekday = 0
            return calendar.date(from: components) ?? Date()
        case .month: return date.addingTimeInterval(-oneDay * 30)
        case .currentMonth:
            var components = calendar.dateComponents([.day, .month, .year], from: date)
            components.day = 1
            return calendar.date(from: components) ?? Date()
        case .year: return date.addingTimeInterval(-oneDay * 365)
        case .currentYear:
            var components = calendar.dateComponents([.day, .month, .year], from: date)
            components.day = 0
            return calendar.date(from: components) ?? Date()
        case .all:
            var components : DateComponents = calendar.dateComponents([.day], from: Date())
            components.day = 1
            components.hour = 0
            components.minute = 0
            components.second = 0
            return calendar.date(from: components) ?? Date()
        case .yesterday:
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            components.hour = 0
            components.minute = 0
            return calendar.date(from: components) ?? Date()
        }
    }
    
    fileprivate static var nullEndDate: Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 24
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }
    
    fileprivate static func unit(for identifier: String) -> HKUnit {
        if identifier == "HKQuantityTypeIdentifierDistanceWalkingRunning" {
            return HKUnit.meter()
        } else if identifier == "HKQuantityTypeIdentifierStepCount" {
            return HKUnit.count()
        } else if identifier == "HKQuantityTypeIdentifierBodyMass" {
            return HKUnit.gramUnit(with: .kilo)
        } else if identifier == "HKQuantityTypeIdentifierHeight" {
            return HKUnit.meterUnit(with: .centi)
        }
        return HKUnit.kilocalorie()
    }
    
    fileprivate static func getTodaySteps(completion: @escaping(Double) -> Void) {
        pedometer.queryPedometerData(from: date(to: .today), to: Date()) { data, error in
            if error != nil {
                print(error!.localizedDescription)
                completion(0)
                return
            }
            completion(data?.numberOfSteps.doubleValue ?? 0)
        }
    }
    
    fileprivate static func getTodayDistance(completion: @escaping(Double) -> Void) {
        pedometer.queryPedometerData(from: date(to: .today), to: Date()) { data, error in
            if error != nil {
                print(error!.localizedDescription)
                completion(0)
                return
            }
            completion(data?.distance?.doubleValue ?? 0)
        }
    }
    
    fileprivate static func getCurrentPedometerData(completion : @escaping(Double, Double) -> Void) {
        pedometer.queryPedometerData(from: date(to: .today), to: Date()) { data, error in
            if error != nil {
                completion(0, 0)
                print(error!.localizedDescription)
                return
            }
            completion(data?.numberOfSteps.doubleValue ?? 0, data?.distance?.doubleValue ?? 0)
        }
    }
    
    fileprivate static func querySteps(at hour: Int, completion: @escaping(Double) -> Void) {
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: Date())
        components.hour = hour
        components.minute = 0
        components.second = 0
        let from : Date = Calendar.current.date(from: components)!
        components.minute = 59
        components.second = 59
        let to : Date = Calendar.current.date(from: components)!
        pedometer.queryPedometerData(from: from, to: to, withHandler: { data, error in
            if error != nil {
                print(error!.localizedDescription)
                completion(0)
                return
            }
            completion(data?.numberOfSteps.doubleValue ?? 0)
        })
    }
    
}
