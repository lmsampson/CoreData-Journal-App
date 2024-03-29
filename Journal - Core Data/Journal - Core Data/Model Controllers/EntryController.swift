//
//  EntryController.swift
//  Journal - Core Data
//
//  Created by Lisa Sampson on 8/20/18.
//  Copyright © 2018 Lisa Sampson. All rights reserved.
//

import Foundation
import CoreData

class EntryController {
    
    init() {
        fetchEntriesFromServer()
    }
    
    func create(title: String, bodyText: String, mood: EntryMood) {
        let moc = CoreDataStack.shared.container.newBackgroundContext()
        moc.performAndWait {
            let entry = Entry(title: title, bodyText: bodyText, mood: mood, context: moc)
            do {
                try CoreDataStack.shared.save(context: moc)
            }
            catch {
                NSLog("Could not save context")
                return
            }
            self.put(entry: entry)
        }
    }
    
    func update(entry: Entry, title: String, bodyText: String, timestamp: Date = Date(), mood: EntryMood = .neutral) {
        
        let moc = CoreDataStack.shared.container.newBackgroundContext()
        
        let objectID = entry.objectID
        
        moc.performAndWait {
            
            do {
                guard let scratch = try moc.existingObject(with: objectID) as? Entry else { return }
                
                scratch.title = title
                scratch.bodyText = bodyText
                scratch.timestamp = timestamp
                scratch.mood = mood.rawValue
                
                try CoreDataStack.shared.save(context: moc)
                put(entry: scratch)
            }
            catch {
                NSLog("Could not save context")
                return
            }
        }
    }
    
    func updateFromRepresentation(entry: Entry, entryRepresentation: EntryRepresentation) {
        
        entry.title = entryRepresentation.title
        entry.bodyText = entryRepresentation.bodyText
        entry.timestamp = entryRepresentation.timestamp
        entry.identifier = entryRepresentation.identifier
        entry.mood = entryRepresentation.mood
    }
    
    func updateEntries(with representations: [EntryRepresentation], context: NSManagedObjectContext) throws {
        
        context.performAndWait {
            
            for entryRepresentation in representations {
                
                guard let identifier = entryRepresentation.identifier else { continue }
                
                if let entry = self.fetchSingleEntryFromPersistentStore(with: identifier, in: context) {
                    self.updateFromRepresentation(entry: entry, entryRepresentation: entryRepresentation)
                } else {
                    let _ = Entry(entryRepresentation: entryRepresentation, context: context)
                }
            }
        }
    }
    
    func delete(entry: Entry) {
        deleteEntryFromServer(entry: entry)
        
        let moc = CoreDataStack.shared.mainContext
        
        
        moc.perform {
            do {
                moc.delete(entry)
                try CoreDataStack.shared.save(context: moc)
            }
            catch {
                NSLog("Could not save context")
                return
            }
        }
    }
    
    func put(entry: Entry, completion: @escaping ((Error?) -> Void) = { _ in }) {
        
        guard let identifier = entry.identifier else { completion(NSError()); return }
        
        let requestURL = baseURL.appendingPathComponent(identifier).appendingPathExtension("json")
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        
        do {
            request.httpBody = try JSONEncoder().encode(entry)
        }
        catch {
            NSLog("Error encoding entry: \(error)")
            completion(error)
            return
        }
        
        URLSession.shared.dataTask(with: request) { (data, _, error) in
            
            if let error = error {
                NSLog("Error PUTing entry to server: \(error)")
                completion(error)
                return
            }
            
            completion(nil)
            }.resume()
        
    }
    
    func deleteEntryFromServer(entry: Entry, completion: @escaping ((Error?) -> Void) = { _ in }) {
        
        guard let identifier = entry.identifier else { completion(NSError()); return }
        
        let requestURL = baseURL.appendingPathComponent(identifier).appendingPathExtension("json")
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { (data, _, error) in
            
            if let error = error {
                NSLog("Error DELETEing entry fromserver: \(error)")
                completion(error)
                return
            }
            
            completion(nil)
            }.resume()
    }
    
    func fetchSingleEntryFromPersistentStore(with identifier: String, in context: NSManagedObjectContext) -> Entry? {
        
        let fetchRequest: NSFetchRequest<Entry> = Entry.fetchRequest()
        
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        
        fetchRequest.predicate = predicate
        
        do {
            return try context.fetch(fetchRequest).first
        }
        catch {
            NSLog("Error fetching single entry: \(error)")
            return nil
        }
    }
    
    func fetchEntriesFromServer(completion: @escaping ((Error?) -> Void) = { _ in }) {
        
        let requestURL = baseURL.appendingPathExtension("json")
        
        URLSession.shared.dataTask(with: requestURL) { (data, _, error) in
            
            if let error = error {
                NSLog("Error fetching entries from server: \(error)")
                completion(error)
                return
            }
            
            guard let data = data else {
                NSLog("No data returned from data entry")
                completion(NSError())
                return
            }
            
            var entryRepresentations: [EntryRepresentation] = []
            
            do {
                entryRepresentations = try Array(JSONDecoder().decode([String: EntryRepresentation].self, from: data).values)
                let moc = CoreDataStack.shared.container.newBackgroundContext()
                try self.updateEntries(with: entryRepresentations, context: moc)
                try CoreDataStack.shared.save(context: moc)
                completion(nil)
            }
            catch {
                NSLog("Error decoding JSON: \(error)")
                completion(error)
                return
            }
        }.resume()
    }
    
    let baseURL = URL(string: "https://journal-core-data.firebaseio.com/")!
    
}
