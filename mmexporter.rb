#!/usr/bin/env ruby

require "dato"
require 'dotenv'
require "active_record"
require "pp"
require "pry"
require "pg"

Dotenv.load
if ENV["DATO_TOKEN"]
  puts "Environment vars loaded"
end


client = Dato::Site::Client.new(ENV["DATO_TOKEN"])

def header(content)
  puts "-----------------------------"
  puts content
  puts "-----------------------------"
end

@publish ||= false
@test    ||= false
@clean   ||= false

ARGV.each do|a|
  case a
    when "publish"
      @publish = true
    when "test"
      @test = true
    when "clean"
      @clean = true
  end
end
header("Performing #{ARGV}")

# Metti i modelli in ordine
# in modo da poter eliminare senza conflitti
# in caso di dipendenze e relazioni

MODELS = {
  author:     {id: ENV["AUTHOR"],     active: false},
  book:       {id: ENV["BOOK"],       active: false},
  collection: {id: ENV["COLLECTION"], active: false},
  supplier:   {id: ENV["SUPPLIER"],   active: false}
}

# Se true, elimina e ricarica le immagini dei modelli attivi
IMAGES = false

def clean_dato(client)
  header("CLEAN DATA ON DATO")

  MODELS.each do |k, model|
    if model[:active]
      header("DELETE #{k}")
      client.items.all(
        "filter[type]" => model[:id],
        "page[limit]"  => ENV["DATO_PAGE_LIMIT"]
      ).each do |item|
        client.items.destroy(item["id"])
        puts "Removing #{k} #{item["id"]}"
      end
    else
      puts "BYPASS #{k}"
    end
  end

  if IMAGES == true
    header("DELETE IMAGES")
    client.uploads.all(
      "filter[type]" => "image",
      "page[limit]" => ENV["DATO_PAGE_LIMIT"]
    ).each do |upload|
      client.uploads.destroy(upload["id"])
      puts "Removing Image #{upload["id"]}"
    end
  end
end

if @publish || @clean
  clean_dato(client)
end

ActiveRecord::Base.establish_connection(
  :adapter  => ENV["DB"],
  :host => "localhost",
  :encoding => "unicode",
  :database => ENV["DB_TABLE"]
)
class Author < ActiveRecord::Base
end

class Collection < ActiveRecord::Base
end

class Book < ActiveRecord::Base
  has_and_belongs_to_many :authors
  belongs_to :collection
end

class Supplier < ActiveRecord::Base
end

class Image < ActiveRecord::Base
  def self.table_name
    "active_admin_gallery_images"
  end

  scope :for_author, ->(id) { where(imageable_id: id, imageable_type: "Author") }
  scope :for_book, ->(id) { where(imageable_id: id, imageable_type: "Book") }
  scope :for_supplier, ->(id) { where(imageable_id: id, imageable_type: "Supplier") }
end

if !@clean

  @mapped_authors = {}
  @mapped_books = {}
  @mapped_collections = {}

  if MODELS[:collection][:active]
    header("COLLECTIONS")
    Collection.all.each do |c|
      puts c.name
      if @publish
        new_collection = client.items.create(
          item_type: MODELS[:collection][:active],
          name: c.name,
          description: c.description
        )
        @mapped_collections[c.id] = new_collection["id"]
      else
        puts c.name
        puts c.description
        @mapped_collections[c.id] = c.id
      end
    end
    header("Collezioni ID convertion")
    puts @mapped_collections
  end

  if MODELS[:author][:active]
    header("AUTORI")

    Author.all.each do |a|
      full_name = "#{a&.first_name.strip} #{a&.last_name.strip}"
      puts "author: #{full_name}"
      img = Image.for_author(a.id).first

      if IMAGES && img.present?
        avatar_path = "http://multimage.s3.amazonaws.com/#{img&.image_uid}"
      else
        avatar_path = nil
      end

      if @publish
        new_author = client.items.create(
          item_type: MODELS[:author][:active],
          full_name: full_name,
          alias: a.alias,
          biography: a.biography,
          country: a.country,
          avatar: avatar_path && client.upload_image(avatar_path)
        )
        @mapped_authors[a.id] = new_author["id"]
      else
        @mapped_authors[a.id] = a.id
      end

      puts "Img path: #{avatar_path}"
    end
    header("Autori ID convertion")
    puts @mapped_authors
  end

  if MODELS[:book][:active]
    header("LIBRI")

    Book.all.each do |b|
      puts b.title

      img = Image.for_book(b.id).first

      if IMAGES && img.present?
        cover_path = "http://multimage.s3.amazonaws.com/#{img&.image_uid}"
      else
        cover_path = nil
      end

      if @publish
        new_book = client.items.create(
          item_type: MODELS[:book][:active],
          title: b.title,
          collection: @mapped_collections[b.collection.id],
          cover: cover_path && client.upload_image(cover_path),
          authors: b.authors.compact.map{|au| @mapped_authors[au.id]},
          description: b.description,
          review: b.review,
          isbn: b.isbn,
          price: b.price,
          discount: b.discount,
          promo: b.promo,
          original_title: b.original_title,
          original_lang: b.original_lang,
          translator: b.translator,
          pages: b.pages,
          stock: b.stock,
          copyright: b.copyright,
          print_year: b.print_year,
          first_print_year: b.first_print_year,
          reprint: b.reprint,
          cover_designer: b.cover_designer,
          layout_artist: b.pager,
          highlight: b.highlight,
          archive: b.archive,
          epub_url: b.epub_url,
          epub_price: b.epub_price
        )
        @mapped_books[b.id] = new_book["id"]
      else
        @mapped_books[b.id] = b.id
      end

      if @test
        puts "Img path: #{cover_path}"
        puts "Ebook price: #{b.epub_price}"
        # b.authors.each do |author|
        #   puts "#{author.first_name} |"
        # end
      end
    end
    header("Libri ID convertion")
    puts @mapped_books
  end

  if MODELS[:supplier][:active]
    header("SUPPLIERS")

    if @publish
      Supplier.all.each do |s|
        puts s.name
        img = Image.for_supplier(s.id).first

        if img.present?
          logo_path = "http://multimage.s3.amazonaws.com/#{img&.image_uid}"
        else
          logo_path = nil
        end

        new_supplier = client.items.create(
          item_type: MODELS[:supplier][:id],
          name: s.name,
          city: s.city,
          region: s.region,
          address: s.address,
          telephone: s.telephone,
          description: s.description,
          url: s.url,
          email: s.email,
          published: s.published,
          logo: logo_path && client.upload_image(logo_path)
        )
      end
    end
  end

  ## TEST

  if @test
    clean_dato(client)

    if MODELS[:collection][:active]
      @test_collection = {}
      new_collection = client.items.create(
        item_type: "26178",
        name: "Collana 1",
        description: nil
      )
      @test_collection[1] = new_collection["id"]
    end

    if MODELS[:author][:active]
      @test_authors = {}
      (1..3).each do |i|
        new_author = client.items.create(
          item_type: "25936",
          full_name: "Ciccio Baiano #{i}",
          alias: "Baianino #{i}",
          biography: nil,
          country: nil,
          avatar: client.upload_image("http://multimage.s3.amazonaws.com/2014/03/06/15/56/27/994/9788886762_168.jpg")
        )
        @test_authors[i] = new_author["id"]
      end
    end

    if MODELS[:book][:active]
      @book_authors = [1, 3]
      new_book = client.items.create(
        item_type: "26183",
        title: "Libro di prova",
        collection: @test_collection[1],
        cover: client.upload_image("http://multimage.s3.amazonaws.com/2017/09/11/16/06/19/142/Coperta_Atti_Simposio2016.jpg"),
        authors: @book_authors.compact.map{|au| @test_authors[au]},
        description: nil,
        review: nil,
        isbn: "XXXXX",
        price: nil,
        discount: nil,
        promo: nil,
        original_title: nil,
        original_lang: nil,
        translator: nil,
        pages: 250,
        stock: 20,
        copyright: nil,
        print_year: nil,
        first_print_year: nil,
        reprint: nil,
        cover_designer: nil,
        layout_artist: nil,
        highlight: true,
        archive: nil,
        epub_url: nil,
        epub_price: nil
      )
    end

    if MODELS[:supplier][:active]
      header("SUPPLIERS")
      Supplier.all.each do |s|
        img = Image.for_supplier(s.id).first
        puts s.name
        puts "Url: #{s.url}"
        puts "Email: #{s.email}"
        puts "Regione: #{s.region}"
        puts "Logo: http://multimage.s3.amazonaws.com/#{img&.image_uid}"

        puts "\n"
      end

      if @test
        @test_supplier = {}
        new_supplier = client.items.create(
          item_type: MODELS[:supplier][:id],
          name: "Distributore xxx",
          city: "Firenze",
          region: "Toscana",
          address: nil,
          telephone: "3445435",
          description: nil,
          url: "https://www.google.com",
          email: "spleenteo@gmail.com",
          published: true,
          logo: client.upload_image("http://multimage.s3.amazonaws.com/2014/03/06/15/56/27/994/9788886762_168.jpg")

        )
        @test_supplier[0] = new_supplier["id"]
      end
    end

  end
end

