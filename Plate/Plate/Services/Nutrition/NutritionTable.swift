import Foundation

/// The bundled food table.
///
/// Stored as text rather than as a Swift array literal for two reasons: a 200-element
/// array of structs is genuinely slow for the type checker, and a pipe-delimited table
/// is something a person can read and edit in a diff.
///
/// Columns: name | aliases | serving label | amount | unit | kcal | protein | carbs | fat | fiber
/// Values are per the stated serving, already scaled — not per 100g.
enum NutritionTable {
    static let raw = """
    Egg|eggs,fried egg,boiled egg|large egg|1|piece|72|6.3|0.4|4.8|0
    Scrambled Eggs|scrambled egg|two eggs|2|piece|182|12.6|1.6|13.6|0
    Omelette|omelet,cheese omelette|three-egg|1|serving|315|21|2.5|24|0
    Bacon|streaky bacon|slice|1|slice|43|3|0.1|3.3|0
    Sausage|breakfast sausage,banger|link|1|piece|85|4.5|1|7|0
    Oatmeal|porridge,oats,overnight oats|prepared bowl|1|bowl|166|5.9|28|3.6|4
    Granola|muesli|half cup|0.5|cup|213|5|36|7|4
    Cereal|corn flakes,breakfast cereal|bowl with milk|1|bowl|207|7|38|3.5|2
    Greek Yogurt|greek yoghurt,yogurt|single-serve cup|1|cup|146|20|8|3.9|0
    Yogurt|yoghurt,plain yogurt|cup|1|cup|149|8.5|11.4|8|0
    Pancakes|pancake,flapjacks|three medium|3|piece|519|11|68|22|2
    Waffle|waffles,belgian waffle|one|1|piece|218|5.9|25|10|1.5
    French Toast|eggy bread|two slices|2|slice|356|11|36|18|1.5
    Bagel|plain bagel|one|1|piece|289|11|56|1.7|2.4
    Toast|white toast,slice of bread|slice|1|slice|79|2.7|14.3|1|0.8
    Whole Wheat Toast|brown toast,wholemeal toast|slice|1|slice|82|4|13.8|1.1|2
    Croissant|butter croissant|one|1|piece|272|5.5|31|14|1.7
    Muffin|blueberry muffin|one|1|piece|426|6|61|18|2
    Donut|doughnut,glazed donut|one|1|piece|269|3.4|31|15|1
    Peanut Butter|pb|tablespoon|2|tablespoon|188|8|6.9|16|1.9
    Almond Butter|nut butter|tablespoon|2|tablespoon|196|6.7|6|18|3.3
    Jam|jelly,preserve|tablespoon|1|tablespoon|56|0.1|13.8|0|0.2
    Butter|salted butter|pat|1|tablespoon|102|0.1|0|11.5|0
    Avocado|avo|half|0.5|piece|161|2|8.5|14.7|6.7
    Avocado Toast|avo toast|one slice|1|slice|245|6.5|23|14|7
    Banana|bananas|medium|1|piece|105|1.3|27|0.4|3.1
    Apple|apples|medium|1|piece|95|0.5|25|0.3|4.4
    Orange|oranges|medium|1|piece|62|1.2|15.4|0.2|3.1
    Strawberries|strawberry|cup|1|cup|49|1|11.7|0.5|3
    Blueberries|blueberry|cup|1|cup|84|1.1|21|0.5|3.6
    Raspberries|raspberry|cup|1|cup|64|1.5|14.7|0.8|8
    Grapes|grape|cup|1|cup|104|1.1|27|0.2|1.4
    Watermelon|melon|cup|1|cup|46|0.9|11.5|0.2|0.6
    Mango|mangoes|cup|1|cup|99|1.4|25|0.6|2.6
    Pineapple|ananas|cup|1|cup|83|0.9|22|0.2|2.3
    Peach|peaches|medium|1|piece|59|1.4|14|0.4|2.3
    Pear|pears|medium|1|piece|101|0.6|27|0.2|5.5
    Kiwi|kiwifruit|one|1|piece|42|0.8|10|0.4|2.1
    Grapefruit|grapefruits|half|0.5|piece|52|1|13|0.2|2
    Dates|medjool dates,date|three|3|piece|200|1.2|54|0.1|4.8
    Raisins|sultanas|small box|0.25|cup|108|1.1|29|0.2|1.4
    Chicken Breast|grilled chicken,chicken|palm-sized fillet|1|serving|231|43.4|0|5|0
    Chicken Thigh|chicken thighs|one thigh|1|piece|177|21.5|0|9.7|0
    Fried Chicken|kfc,chicken wings|two pieces|2|piece|432|33|16|25|1
    Chicken Nuggets|nuggets|six|6|piece|287|15|17|18|1
    Rotisserie Chicken|roast chicken|cup shredded|1|cup|239|38|0|9|0
    Turkey|roast turkey,turkey breast|slices|3|ounce|125|26|0|1.8|0
    Ground Beef|mince,beef mince|quarter pound cooked|4|ounce|287|26|0|20|0
    Steak|sirloin,ribeye,beef steak|eight ounce|8|ounce|544|62|0|32|0
    Meatballs|meatball|four|4|piece|264|18|8|18|0.8
    Pork Chop|pork|one chop|1|piece|264|38|0|11.5|0
    Bacon Cheeseburger|burger,cheeseburger,hamburger|one|1|piece|711|38|42|43|2.5
    Hot Dog|hotdog,frankfurter|one with bun|1|piece|314|11|26|18|1
    Lamb|lamb chop,roast lamb|three ounce|3|ounce|250|21|0|18|0
    Salmon|grilled salmon,salmon fillet|fillet|1|serving|367|39|0|22|0
    Tuna|canned tuna,tuna steak|can drained|1|serving|191|42|0|1.4|0
    Shrimp|prawns,prawn,shrimps|six large|6|piece|84|18|0.2|0.9|0
    Cod|white fish,haddock|fillet|1|serving|189|41|0|1.5|0
    Fish and Chips|fish n chips|one order|1|plate|843|43|85|38|6
    Sushi Roll|sushi,maki,california roll|six pieces|6|piece|255|9|38|7|2.5
    Sashimi|raw fish|six pieces|6|piece|122|24|0|2.5|0
    Tofu|beancurd|half block|0.5|serving|181|20|4.4|11|2
    Tempeh|fermented soy|three ounce|3|ounce|166|17|8|9|6
    Lentils|dal,daal,lentil soup|cup cooked|1|cup|230|18|40|0.8|15.6
    Chickpeas|garbanzo,garbanzos|cup|1|cup|269|14.5|45|4.2|12.5
    Black Beans|beans,frijoles|cup|1|cup|227|15|41|0.9|15
    Hummus|houmous|quarter cup|0.25|cup|103|3|9|6|3
    Falafel|falafels|four balls|4|piece|228|9|22|12|5
    Edamame|soybeans|cup|1|cup|188|18.5|14|8|8
    Peanuts|groundnuts|handful|1|handful|161|7.3|4.6|14|2.4
    Almonds|almond|handful|1|handful|164|6|6.1|14|3.5
    Walnuts|walnut|handful|1|handful|185|4.3|3.9|18.5|1.9
    Cashews|cashew|handful|1|handful|157|5.2|8.6|12.4|0.9
    Pistachios|pistachio|handful|1|handful|159|5.7|7.7|12.8|3
    Trail Mix|nuts and raisins|quarter cup|0.25|cup|173|5.2|16.8|11|2
    White Rice|rice,jasmine rice,steamed rice|cup cooked|1|cup|205|4.3|45|0.4|0.6
    Brown Rice|wholegrain rice|cup cooked|1|cup|218|4.5|46|1.6|3.5
    Fried Rice|egg fried rice|cup|1|cup|333|11|43|13|1.8
    Quinoa|quinua|cup cooked|1|cup|222|8.1|39|3.6|5.2
    Couscous|cous cous|cup cooked|1|cup|176|6|36|0.3|2.2
    Pasta|spaghetti,penne,noodles,fusilli|cup cooked|1|cup|221|8.1|43|1.3|2.5
    Spaghetti Bolognese|bolognese,pasta bolognese|plate|1|plate|588|29|72|20|6
    Mac and Cheese|macaroni cheese,mac n cheese|cup|1|cup|376|13.5|44|16|1.8
    Pesto Pasta|pasta pesto|plate|1|plate|614|17|69|29|4
    Lasagna|lasagne|slice|1|slice|408|24|31|20|3
    Ramen|ramen noodles,instant noodles|bowl|1|bowl|436|13|58|17|3.5
    Pad Thai|padthai|plate|1|plate|639|24|76|26|4
    Pho|beef pho,vietnamese noodle soup|bowl|1|bowl|415|30|52|8|3
    Udon|udon noodles|bowl|1|bowl|359|12|71|2.5|4
    Bread Roll|dinner roll,bun|one|1|piece|120|4|22|1.8|1
    Pita|pitta,flatbread|one|1|piece|165|5.5|33|0.7|1.3
    Tortilla|flour tortilla|one|1|piece|146|4|24|3.5|1.5
    Naan|naan bread|one|1|piece|262|8.7|45|5.1|2
    Baguette|french bread|six inch|1|serving|185|6|36|1|1.5
    Sandwich|sarnie,sub|one|1|piece|412|22|42|17|3
    Club Sandwich|clubhouse|one|1|piece|590|33|46|30|3
    BLT|bacon lettuce tomato|one|1|piece|450|18|39|25|3
    Grilled Cheese|cheese toastie,toastie|one|1|piece|422|16|33|25|2
    Wrap|chicken wrap,burrito wrap|one|1|piece|437|24|45|18|4
    Burrito|bean burrito|one|1|piece|684|27|84|26|11
    Taco|tacos|two|2|piece|340|17|30|17|5
    Quesadilla|quesadillas|one|1|piece|528|22|41|30|3
    Nachos|loaded nachos|plate|1|plate|692|20|66|39|7
    Pizza|pizza slice,pepperoni pizza|two slices|2|slice|570|24|68|22|3
    Margherita Pizza|margarita pizza|two slices|2|slice|498|21|64|17|3
    Caesar Salad|caesar|bowl|1|bowl|362|11|13|31|3
    Greek Salad|horiatiki|bowl|1|bowl|211|7|11|16|3.5
    Garden Salad|side salad,green salad|bowl|1|bowl|68|2.5|9|2.5|3
    Chicken Salad|grilled chicken salad|bowl|1|bowl|385|38|13|20|4
    Coleslaw|slaw|half cup|0.5|cup|138|0.9|11|10|1.4
    Potato Salad|tater salad|half cup|0.5|cup|179|2.1|14|13|1.5
    Soup|vegetable soup,broth|bowl|1|bowl|145|6|20|4.5|3.5
    Chicken Noodle Soup|chicken soup|bowl|1|bowl|175|12|18|5|1.5
    Tomato Soup|cream of tomato|bowl|1|bowl|196|4.5|24|9|2.5
    Miso Soup|miso|bowl|1|bowl|66|4|7|2.2|1
    Chili|chilli,chili con carne|bowl|1|bowl|374|26|32|15|9
    Curry|chicken curry,vegetable curry|plate with rice|1|plate|628|31|66|26|6
    Tikka Masala|chicken tikka masala|plate with rice|1|plate|712|38|68|32|5
    Butter Chicken|murgh makhani|plate with rice|1|plate|745|36|66|38|4
    Biryani|biriyani|plate|1|plate|589|24|72|22|4
    Sweet Potato Curry|vegetable curry,veg curry|bowl|1|bowl|412|9|62|15|10
    Stir Fry|vegetable stir fry,stirfry|plate|1|plate|398|22|42|16|6
    Sweet and Sour Chicken|sweet n sour|plate|1|plate|628|28|76|24|3
    Dumplings|gyoza,potstickers,dim sum|six|6|piece|338|14|38|14|2
    Spring Rolls|spring roll,egg roll|two|2|piece|226|5|26|11|2
    Shawarma|chicken shawarma,doner|wrap|1|piece|612|38|52|28|4
    Kebab|kebabs,shish kebab|skewer|1|piece|286|28|6|17|1
    Gyro|gyros|one|1|piece|593|33|48|30|3
    Sushi Bowl|poke bowl,poke|bowl|1|bowl|548|32|64|17|5
    Burrito Bowl|chipotle bowl,rice bowl|bowl|1|bowl|665|33|72|27|11
    Shepherds Pie|cottage pie|plate|1|plate|478|26|43|22|5
    Roast Dinner|sunday roast|plate|1|plate|712|45|62|30|8
    Meatloaf|meat loaf|slice|1|slice|294|21|12|18|1
    Mashed Potatoes|mash,mashed potato|cup|1|cup|237|4|35|9|3
    Baked Potato|jacket potato|medium|1|piece|161|4.3|37|0.2|3.8
    French Fries|fries,chips|medium portion|1|serving|365|4|48|17|4
    Sweet Potato Fries|sweet potato chips|portion|1|serving|312|3|46|13|6
    Roast Potatoes|roasties|cup|1|cup|227|4|38|7|4
    Hash Browns|hashbrown|two|2|piece|282|3|30|17|3
    Onion Rings|onion ring|portion|1|serving|411|5|46|23|3
    Broccoli|tenderstem|cup|1|cup|55|3.7|11|0.6|5
    Spinach|baby spinach|cup cooked|1|cup|41|5.3|6.8|0.5|4.3
    Kale|curly kale|cup|1|cup|33|2.9|6|0.5|2.6
    Carrots|carrot|cup|1|cup|52|1.2|12|0.3|3.6
    Green Beans|string beans|cup|1|cup|44|2.4|10|0.3|4
    Asparagus|asparagus spears|cup|1|cup|27|3|5.2|0.2|2.8
    Brussels Sprouts|sprouts|cup|1|cup|56|4|11|0.8|4.1
    Cauliflower|cauli|cup|1|cup|29|2.3|5.3|0.6|2.9
    Zucchini|courgette|cup|1|cup|27|2|4.9|0.5|1.6
    Mushrooms|mushroom|cup|1|cup|44|3.4|8|0.7|2.3
    Bell Pepper|capsicum,peppers|one|1|piece|31|1|7.2|0.3|2.5
    Tomato|tomatoes|medium|1|piece|22|1.1|4.8|0.2|1.5
    Cucumber|cukes|cup|1|cup|16|0.7|3.8|0.1|0.5
    Corn|sweetcorn,corn on the cob|cob|1|piece|99|3.5|22|1.5|2.4
    Peas|garden peas|cup|1|cup|134|8.6|25|0.4|8.8
    Roasted Vegetables|roast veg,veggies|cup|1|cup|142|3.5|20|6|5
    Cheddar Cheese|cheese,cheddar|slice|1|slice|113|7|0.4|9.3|0
    Mozzarella|fresh mozzarella|ounce|1|ounce|85|6.3|0.6|6.3|0
    Parmesan|parmigiano|tablespoon|2|tablespoon|43|3.9|0.4|2.9|0
    Cottage Cheese|curds|half cup|0.5|cup|103|12|4.3|4.5|0
    Feta|feta cheese|ounce|1|ounce|75|4|1.2|6|0
    Cream Cheese|philadelphia|tablespoon|2|tablespoon|102|1.8|1.6|10|0
    Milk|whole milk,semi skimmed|cup|1|cup|149|7.7|11.7|8|0
    Oat Milk|oatly|cup|1|cup|120|3|16|5|2
    Almond Milk|nut milk|cup|1|cup|39|1.5|3.4|2.5|0.5
    Protein Shake|whey shake,protein powder|scoop with water|1|scoop|123|24|3|1.5|1
    Smoothie|fruit smoothie|medium|1|serving|278|6|56|3.5|5
    Coffee|black coffee,americano|cup|1|cup|2|0.3|0|0|0
    Latte|caffe latte,flat white|medium|1|serving|190|10|19|7|0
    Cappuccino|cappucino|medium|1|serving|120|6.5|12|4.5|0
    Tea|black tea,green tea|cup|1|cup|2|0|0.5|0|0
    Orange Juice|oj,juice|glass|1|cup|112|1.7|26|0.5|0.5
    Soda|coke,cola,soft drink|can|1|serving|139|0|39|0|0
    Diet Soda|diet coke,zero sugar|can|1|serving|2|0|0.4|0|0
    Beer|lager,pint of beer|pint|1|serving|208|1.8|17|0|0
    Wine|red wine,white wine|glass|1|serving|125|0.1|3.8|0|0
    Whiskey|whisky,spirits,vodka,gin|shot|1|serving|97|0|0|0|0
    Cocktail|margarita,mojito|one|1|serving|222|0.2|24|0.1|0
    Water|sparkling water|glass|1|cup|0|0|0|0|0
    Chocolate|dark chocolate,milk chocolate|bar|1|serving|235|3.4|26|13|3
    Cookie|biscuit,cookies|two|2|piece|156|1.8|21|7.4|0.7
    Brownie|brownies|one|1|piece|243|3|38|10|1.5
    Cake|birthday cake,sponge cake|slice|1|slice|352|4|51|15|1
    Cheesecake|cheese cake|slice|1|slice|401|7|32|28|0.5
    Ice Cream|gelato|two scoops|2|scoop|273|4.6|31|14.5|1
    Apple Pie|pie|slice|1|slice|411|3.7|58|19|2
    Croissant Sandwich|breakfast sandwich|one|1|piece|498|22|38|28|2
    Chips|crisps,potato chips|small bag|1|serving|152|2|15|10|1.3
    Popcorn|popped corn|three cups|3|cup|93|3|19|1.1|3.6
    Pretzels|pretzel|handful|1|handful|108|2.6|22|0.8|0.9
    Granola Bar|cereal bar,protein bar|one|1|piece|194|8|24|7|3
    Rice Cake|rice cakes|two|2|piece|70|1.4|14.6|0.5|0.6
    Crackers|cream crackers|five|5|piece|80|1.6|13|2.5|0.5
    Olives|olive|ten|10|piece|58|0.4|3.1|5.4|1.6
    Pickles|gherkins,pickle|spear|1|piece|4|0.2|0.8|0|0.4
    Salsa|pico de gallo|quarter cup|0.25|cup|18|0.9|4|0.1|1
    Guacamole|guac|quarter cup|0.25|cup|91|1.2|5|8|3.5
    Ketchup|tomato sauce|tablespoon|1|tablespoon|19|0.2|4.7|0|0.1
    Mayonnaise|mayo|tablespoon|1|tablespoon|94|0.1|0.1|10.3|0
    Mustard|dijon|teaspoon|1|teaspoon|3|0.2|0.3|0.2|0.1
    Olive Oil|oil,cooking oil|tablespoon|1|tablespoon|119|0|0|13.5|0
    Soy Sauce|shoyu|tablespoon|1|tablespoon|9|1.3|0.8|0|0
    Ranch Dressing|ranch|tablespoon|2|tablespoon|129|0.4|1.8|13.4|0
    Honey|hunny|tablespoon|1|tablespoon|64|0.1|17.3|0|0
    Maple Syrup|syrup|tablespoon|1|tablespoon|52|0|13.4|0|0
    Sugar|white sugar|teaspoon|1|teaspoon|16|0|4.2|0|0
    """
}
