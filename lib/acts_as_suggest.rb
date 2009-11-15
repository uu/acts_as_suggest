require 'text'

module ActiveRecord #:nodoc:
  module Acts #:nodoc:
    module Suggest#:nodoc:

      def self.included(base) #:nodoc:
        base.extend ClassMethods
      end

      module ClassMethods #:nodoc:
        def acts_as_suggest
          extend ActiveRecord::Acts::Suggest::SingletonMethods
        end
      end

    # When searching for the word "honnolullu", Google will promptly suggest "Did you mean: honolulu". This small module provides a +suggest+ method
    # which enables developers to add this functionality to any model, basing the suggestion on the existing values in the table. 
    # Just place <tt>acts_as_suggest</tt> in a given model to mixin the method +suggest+.
    #
    # Example:
    #   class Person < ActiveRecord::Base
    #     acts_as_suggest
    #   end
    #
    # and then to retrieve suggestions:
    #
    #  MyModel.suggest(:field_name, searched_value, optional_treshold)
    # or 
    #  MyModel.suggest([:field1, :field2, ...], searched_value, optional_treshold)
    # 
    # The field_name(s) specify in what columns we need to look for the suggested/existing values.
    # The searched_value is the supposedly misspelled string for which we want to retrieve corrections.
    # The optional_treshold defines the tolerance level in determining the Levenshtein distance between the searched string and existing values in the database.
    # If omitted, this value is calculated based on the length of the string.
      module SingletonMethods
        # Output:
        # * If the value of +word+ exists for the specified column(s) => Records are returned (equivalent to a find(:all, :conditions => '...')
        # * If the value doesn't exist in the table, but there are similar existing ones in the specified field(s) => An array of possible intended values is returned
        # * If the value doesn't exist in the table and there are not enough similar strings stored => [] is returned
        #
        # Examples:
        #   Person.suggest(:city, 'Rome') #=> [#<Post:0x556fcd4 @attributes={"city"=>"Rome", "name"=>"Antonio", "id"=>"1","country"=>"Italy"}>] 
        #   Person.suggest(:city, 'Rom') #=> ["Rome", "Roma"]
        #   Person.suggest([:city, :country], 'Romai'] #=> ["Rome", "Roma", "Romania"] 
        #   Person.suggest(:city, 'Vancovvver', 1) #=> []
        def suggest(fields, word, treshold = nil)
          similar_results = []
          # Define treshold if not explicitly specified
          unless treshold
            if word.size <= 4
              treshold = 1
            else
              # Longer words should have more tolerance
              treshold = word.size/3
            end
          end
          
          # Checks if an array of fields is passed
          if fields.kind_of?(Array) 
            conditions = ""
            # Hash that will contain the values for the matching symbol keys
            param_hash = {}
            # Builds the conditions for the find method
            # and fills the hash for the named parameters
            fields.each_with_index do |field, i|
              param_hash[field] = word
              if fields.size > 1 && i < fields.size - 1
                conditions += "#{field} = :#{field} OR " 
              else
                conditions += "#{field} = :#{field}"
              end
            end
            # Search multiple fields through named bind variables 
            # (for safety against tainted data)
            search_results = self.find(:all, :conditions => [conditions, param_hash])
          else
            # Only one field to search in
            search_results = self.find(:all, :conditions => ["#{fields} = ?", word])
          end
       
          # Checks if +word+ exist in the requested field(s)
          if search_results.empty?
            # Retrieves list of all existing values in the table
            all_results = self.find(:all)                     
            # Checks if the table is empty
            unless all_results.empty?
              all_results.each do |record|
                if fields.kind_of?(Array)
                  # Adds all the strings that are similar to the one passed as a parameter (searching in the specified fields)
                  fields.each {|field| similar_results << record.send(field).to_s if record.send(field).to_s.similar?(word, treshold)}
                else
                  # Adds all the strings that are similar to the one passed as a parameter (searching the single field specified only)
                  similar_results << record.send(fields).to_s if record.send(fields).to_s.similar?(word, treshold)
                end
              end
            end
            # Remove multiple entries of the same string from the results
            return similar_results.uniq
          else
            # The value exists in the table,
            # the corrisponding records are therefore returned in an array
            return search_results
          end
          
        end

      end
      
    end
  end
end

class String
  # Levenshtein distance, used to determine the minimum number 
  # of changes needed to modify a string into another one.
  # It uses the Text gem for its UTF-8 enabled comparisons.
  def distance(other)
    Text::Levenshtein::distance(self, other)
  end
  
  # Determines if two strings are similar based
  # on a provided treshold.
  def similar?(other, threshold = 2)
    self.distance(other) <= threshold ? true : false
  end
end