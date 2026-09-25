"""Message Shield synthetic corpus templates (train/val/test pools).

Everything here is authored for this project (no third-party corpus is
required, so there is no licensing constraint on the shipped test set).
`train_model.py` can optionally merge an open dataset that the developer
downloads themselves -- see tool/message_shield/README.md.

Splitting rule: templates are assigned to train/val/test by a stable hash of
the template text, so no template ever appears in two splits (no leakage).
"""

BANKS = [
    "SBI", "HDFC Bank", "ICICI Bank", "Axis Bank", "Kotak Mahindra Bank",
    "Punjab National Bank", "Bank of Baroda", "Canara Bank",
]
WALLETS = ["Paytm", "PhonePe", "Google Pay", "Amazon Pay"]
COURIERS = ["FedEx", "DHL", "Blue Dart", "DTDC", "India Post", "Ekart"]
GOV = ["Income Tax Department", "RBI", "TRAI", "UIDAI", "Cyber Crime Cell", "Customs Department"]
BRANDS = ["Amazon", "Flipkart", "Myntra", "BigBasket", "Swiggy", "Zomato", "Netflix", "Jio"]
NAMES = ["Rahul", "Priya", "Anita", "Sunil", "Meera", "Arjun", "Kavita", "Deepak"]
DAYS = ["today", "tomorrow", "Monday", "this week", "in 24 hours", "within 2 hours"]
MONTHS = ["January", "March", "June", "September", "November"]
ITEMS = ["earphones", "a mobile cover", "the grocery order", "your order", "the shoes"]

AMOUNTS = ["499", "1,250", "2,499", "4,999", "9,999", "12,500", "25,000", "49,000", "1,20,000"]
AMOUNTS_BIG = ["50,000", "1,00,000", "2,50,000", "5,00,000", "10,00,000"]

SAFE_URLS = [
    "https://onlinesbi.sbi", "https://www.hdfcbank.com", "https://www.icicibank.com",
    "https://www.amazon.in/orders", "https://www.netflix.com/youraccount",
    "https://www.flipkart.com/helpcentre", "https://jio.com/myaccount",
]
SUSPICIOUS_URLS = [
    "http://sbi-kyc-update.xyz/verify", "http://bit.ly/3xkYc2", "http://103.24.55.19/otp",
    "http://hdfc-secure-login.top/verify-account", "http://rbi-refund.online/claim",
    "http://amaz0n-delivery.click/pay-fee", "http://tinyurl.com/kyc-verify",
    "http://secure-icici.update-account.info/login", "http://customs-clearance.help/pay",
    "http://wa.me/919876500011", "http://t.me/vip_trading_profit_99",
    "http://paytm-kyc.online/update?id=9981", "http://sbi.your-verify-login.ru/otp",
]
UPI_IDS = ["refund.help@ybl", "customercare.axis@paytm", "kyc.update@okaxis", "loan.release@okhdfcbank"]
PHONES = ["+919876500011", "+918812345678", "18001234567", "9012345678"]
DIGITS = ["482913", "739201", "204857", "918273", "555123", "660412"]

SLOT_VALUES = {
    "bank": BANKS,
    "wallet": WALLETS,
    "courier": COURIERS,
    "gov": GOV,
    "brand": BRANDS,
    "name": NAMES,
    "day": DAYS,
    "month": MONTHS,
    "item": ITEMS,
    "amount": AMOUNTS,
    "amount2": AMOUNTS_BIG,
    "amount3": AMOUNTS[2:6],
    "safe_url": SAFE_URLS,
    "url": SUSPICIOUS_URLS,
    "upi": UPI_IDS,
    "phone": PHONES,
    "digits": DIGITS,
}

# ---------------------------------------------------------------------------
# Templates per class
# ---------------------------------------------------------------------------

TEMPLATES = {
    # ---------------------------------------------------------------- legit
    "legitimate": [
        "{digits} is your OTP for {bank} net banking login. Do not share this code with anyone, including bank staff. Valid for 10 minutes.",
        "Your OTP is {digits}. Never share your OTP, PIN or CVV with anyone. {bank} never asks for it.",
        "{digits} is the one time password for your {bank} card transaction ending 4321. Do not share it.",
        "Rs.{amount} has been debited from your {bank} account XX4321 on {day}. If this was not you, call our official helpline 1800123456.",
        "Rs.{amount} credited to your {bank} account XX4321 towards salary. Available balance updated in the app.",
        "Your {bank} account statement for {month} is ready. Login to the official app to view it.",
        "Reminder: your electricity bill of Rs.{amount} is due on {day}. Pay through the official app or website.",
        "{courier}: your order for {item} has been delivered. Thank you for shopping with {brand}.",
        "{brand} sale is live: flat 25 percent off on selected items this weekend. To unsubscribe reply STOP.",
        "Your {bank} KYC is already updated and verified. No action is required from your side.",
        "Hi {name}, are we still meeting at 7 in the evening? Let me know if the time works.",
        "Mom I will be a bit late today, please start dinner without me.",
        "Hey, I have emailed the documents you asked for. Check when you get time.",
        "Your interview is scheduled on {day} at 11 am. Please carry a valid photo id.",
        "Your Aadhaar update request has been received. There is no fee for updating Aadhaar details.",
        "Ticket number 44512 for your complaint has been resolved. Reply here if you still need help.",
        "{brand} order 7745123 is out for delivery and will reach you by 7 pm today.",
        "Your {wallet} wallet balance is Rs.{amount}. You can view the full statement in the app.",
        "Thanks for your payment of Rs.{amount} to {brand}. Your invoice is attached in the app.",
        "Aapke {bank} account me Rs.{amount} credit hua hai. Koi OTP ya PIN kisi ke saath share na karein.",
        "Aapka OTP {digits} hai. Bank kabhi bhi OTP nahi maangta, ise kisi ke saath share na karein.",
        "मम्मी मैं आज देर से आऊंगा, खाना रख दो।",
        "आपका बिजली बिल Rs.{amount} {day} को देय है। आधिकारिक ऐप से भुगतान करें।",
        "Meeting moved to 4 pm, same link as before. Talk soon.",
        "Interview call scheduled for tomorrow, HR will call from the office number.",
    ],

    # ------------------------------------------------------------ bulk spam
    "spam": [
        "HOT DEAL!! Flat 70 percent off on all recharge packs, buy now. Limited period offer.",
        "Congratulations! You have been selected for a free gift. Reply YES to claim it now.",
        "Lowest interest personal loans, instant approval, zero documents needed. Contact {phone}.",
        "Buy one get one free on all products this week only. Visit {url} today.",
        "Increase your followers instantly and grow your business. Reply for price list.",
        "Lose 8 kg in 7 days guaranteed with our new ayurvedic plan. Call {phone} now.",
        "Earn money online fast, work from home and get daily payouts. Reply START for details.",
        "Forward this message to 10 friends to receive good luck today.",
        "New adult chat service in your city, click {url} to join.",
        "Sabse sasta recharge aur data plan yahin milega, abhi buy karein limited offer.",
        "Get a free {brand} gift voucher worth Rs.{amount}, limited stock, reply now.",
        "Sasta loan approval in 5 minutes, no cibil check, call {phone}.",
        "Double your earnings with our simple mobile app, download and start today.",
        "Biggest sale of the year started, upto 90 percent off, hurry offer ends tonight.",
        "Your lucky number is selected, buy our product and win exciting prizes.",
    ],

    # ------------------------------------------------------------- phishing
    "phishing": [
        "Dear customer, your {bank} account will be blocked today. Verify your details immediately at {url}",
        "Your KYC is expired. Update KYC now at {url} or your account will be suspended within 24 hours.",
        "Your parcel is held at customs. Pay the clearance fee of Rs.{amount} at {url}",
        "{brand}: your payment failed. Update your card details at {url} to avoid service interruption.",
        "You have a pending refund of Rs.{amount}. Claim it now at {url} before it expires.",
        "Unusual login detected on your {bank} account. Confirm your identity at {url}",
        "Your electricity bill is pending, service will be disconnected {day}. Pay at {url} to avoid disconnection.",
        "Your account has been temporarily locked due to security reasons. Unlock at {url}",
        "Your {wallet} account needs re-verification, complete it at {url} within 12 hours.",
        "Dear user, your {courier} shipment is on hold, update your address and pay at {url}",
        "Government subsidy of Rs.{amount} is pending in your name. Claim at {url} with your bank details.",
        "Your {bank} debit card has been suspended. Reactivate at {url} immediately.",
        "{brand} security alert: someone tried to access your account. Verify at {url}",
        "Update your PAN with your bank account today at {url} to avoid account freeze.",
    ],

    # ------------------------------------------------------ financial fraud
    "financial_fraud": [
        "I am {name} from {bank} fraud department. Your card is compromised, confirm your 16 digit card number and CVV so we can block it.",
        "Send Rs.{amount} to {upi} to reverse the wrong transaction, we will refund it instantly.",
        "Your refund of Rs.{amount} is pending. Share the 6 digit code we just sent to complete the refund process.",
        "Pay the processing fee of Rs.{amount} to release your approved loan of Rs.{amount2}.",
        "Pay Rs.{amount} to {upi} to claim your matured policy amount of Rs.{amount2} today.",
        "An extra amount was credited to your account by mistake. Please transfer Rs.{amount} back to {upi} immediately.",
        "To cancel the transaction of Rs.{amount} you must approve the collect request in your UPI app right now.",
        "Your card is blocked, share the OTP and CVV with our officer to unblock it immediately.",
        "Sir we need your debit card number, expiry date and CVV to process the refund of Rs.{amount}.",
        "Your EMI has failed, pay Rs.{amount} immediately on {upi} to avoid credit score damage.",
        "Transfer Rs.{amount} to {upi} for customs duty and your money will be refunded with interest.",
        "Our officer will guide you, just approve the payment request of Rs.{amount} twice as verification.",
    ],

    # ------------------------------------------------------ credential theft
    "credential_theft": [
        "Bank security team: to prevent unauthorised access, share the OTP you just received with our officer immediately.",
        "Please share your 6 digit verification code to complete your KYC verification today.",
        "Sir I am sending an OTP on your number, please tell me the code to activate your new SIM card.",
        "Enter your net banking user id, password and PIN at {url} to avoid account deactivation.",
        "We need your CVV and card expiry to reverse the failed charge, please provide the details now.",
        "Your login session will expire, reply with your user id and password to continue using the service.",
        "{digits} is the code sent to your phone, share it with me to verify your identity for the refund.",
        "Do not tell anyone, just read the OTP to me for account verification, this call is recorded.",
        "Aapko OTP aaya hoga, usko mujhe bata do warna account band ho jayega.",
        "{digits} OTP अभी अधिकारी को शेयर करें वरना खाता बंद हो जाएगा।",
        "Please forward the WhatsApp code you received to this number to keep your account active.",
        "Share the UPI PIN with our support agent to complete the pending verification.",
    ],

    # -------------------------------------------------------- impersonation
    "impersonation": [
        "This is {bank} customer care. Your account is used for money laundering, you will be arrested if you do not cooperate.",
        "{gov}: your PAN is linked to illegal transactions. Pay the penalty of Rs.{amount} immediately or face legal action.",
        "Cyber crime branch: an FIR has been registered against you. Join this video call at {url} for verification.",
        "This is the police, your Aadhaar was found in a drugs case. Do not tell anyone or you will be arrested today.",
        "{courier}: your parcel contains illegal items, customs will arrest you unless you pay Rs.{amount}.",
        "{gov}: your mobile number will be disconnected in 2 hours due to illegal activity. Press 1 to talk to an officer.",
        "I am calling from {bank} head office, cooperate with me or your account will be frozen by evening.",
        "Government officer here, your {gov} scheme installment needs your Aadhaar and bank details, share them now.",
        "This is {bank} compliance department. A legal case has been filed, you must pay Rs.{amount} as settlement.",
        "I am from {gov}, a court notice is issued in your name, pay Rs.{amount} to close the case immediately.",
        "{wallet} support here, your account is under investigation for fraud, do not discuss this with anyone.",
        "TRAI order: your number is being misused, transfer Rs.{amount} for verification or the number will be blocked.",
    ],

    # -------------------------------------------------- social engineering
    "social_engineering": [
        "Please help me, I met with an accident, I need Rs.{amount} urgently, transfer to {upi} and do not tell anyone.",
        "Mummy this is my new number, my phone broke, I need money urgently for the hospital bill.",
        "I am your daughter's friend, she is in trouble, you must send the money immediately and keep this a secret.",
        "Your brother is in police custody, arrange Rs.{amount} in the next 30 minutes or he will be hurt.",
        "I have your private photos and chats, pay Rs.{amount} in crypto or I will send them to your contacts.",
        "If you do not pay within 24 hours I will upload your chats online, transfer crypto to this wallet now.",
        "We recorded your parcel with illegal items, pay Rs.{amount} to avoid jail, do not tell the police.",
        "This is your final warning, pay immediately or your family will be harmed.",
        "Your son has been detained at the airport, pay Rs.{amount} right now and stay on the call.",
        "I am the police officer handling your case, you are under digital arrest, keep the video call on and transfer the money.",
        "Do not disconnect this call, you are being watched, send money as instructed and tell nobody.",
        "Pay the fine now or a warrant will be issued in your name tonight, we are monitoring your location.",
        "Emergency: your relative is in ICU, we need the payment in 20 minutes, send it to {upi}, keep quiet about this.",
    ],

    # ------------------------------------------------------ investment scam
    "investment_scam": [
        "Join our VIP trading group, 300 percent guaranteed profit in 7 days. Link {url}",
        "Invest only Rs.{amount} and earn Rs.{amount2} daily with our assured plan. WhatsApp {phone}",
        "Our SEBI registered expert will double your capital in the equity market with guaranteed returns, join {url}",
        "Crypto mining plan with 5 percent daily fixed return, invest now and withdraw anytime.",
        "Work from home data entry job, earn Rs.{amount} per day, pay a registration fee of Rs.{amount3} to start.",
        "{brand} selected you for a part time typing job, deposit Rs.{amount} for the training kit today.",
        "Loan approved instantly, pay only the processing fee of Rs.{amount} to {upi} and receive the amount today.",
        "Part time job with simple mobile tasks and daily payout of Rs.{amount}, no experience needed, dm for details.",
        "Our trading bot delivers 42 percent monthly returns, deposit USDT to this wallet and start earning.",
        "Guaranteed doubling scheme for our members, invest Rs.{amount2} and get double in 90 days, no risk.",
        "Sarkari yojana ke tahat free loan mil raha hai, sirf Rs.{amount} processing fee bhejein {upi} par.",
        "Stock market tip with 95 percent accuracy, join paid group, pay Rs.{amount} to {upi} now.",
    ],

    # ----------------------------------------------------------- reward scam
    "reward_scam": [
        "{bank} anniversary offer: you won a lottery of Rs.{amount2}! Pay Rs.{amount} as processing fee to claim it.",
        "Your number has won Rs.{amount2} in the lucky draw, share your bank details and IFSC to receive the prize.",
        "Congratulations! You received a cashback of Rs.{amount}, claim it within 30 minutes at {url}",
        "Spin and win: you are the lucky winner of a smartphone, pay the delivery charge of Rs.{amount}.",
        "Your scratch card won Rs.{amount}, tell us the code we sent to your phone to credit the amount.",
        "You are selected for a free giveaway, just pay the courier charge to receive your prize.",
        "Aapka number lucky draw me select hua hai, prize paane ke liye Rs.{amount} bhejein {upi} par.",
        "{brand} gift: claim your Rs.{amount2} voucher, pay Rs.{amount} verification charge at {url}",
        "Prize money of Rs.{amount2} is waiting in your name, pay the tax of Rs.{amount} before {day}.",
        "You won a lottery from a foreign country, send your Aadhaar and bank details to claim Rs.{amount2}.",
    ],

    # --------------------------------------------------------- delivery scam
    "delivery_scam": [
        "Your parcel could not be delivered due to an incomplete address. Pay the redelivery fee of Rs.{amount} at {url}",
        "{courier}: your package is stuck at customs, pay the clearance fee of Rs.{amount} to release it or it will be destroyed.",
        "We attempted delivery today and you were unavailable, reschedule by paying Rs.{amount} at {url} within 12 hours.",
        "Your international courier is held, illegal items were found, pay a customs penalty of Rs.{amount} or a police case will be filed.",
        "Order delivery failed: update your address and pay the handling fee of Rs.{amount} here {url}",
        "{courier} notice: your shipment is pending because duty of Rs.{amount} is unpaid, pay at {url} to avoid return.",
        "Your {brand} order is on hold, pay Rs.{amount} to {upi} for address verification.",
        "Parcel returned to warehouse, pay Rs.{amount} within 6 hours at {url} to get it delivered again.",
    ],
}

# Obfuscated / adversarial template pool (deliberately altered scam wording).
# These are added on top of the augmentor output so the held-out test set has
# a measurable adversarial slice.
ADVERSARIAL_TEMPLATES = [
    ("credential_theft", "B@nk security : plz sh@re the 0TP u just received with our oficer immediatly ."),
    ("credential_theft", "Sir O T P bata dijiye verification ke liye warna a/c bnd ho jayega"),
    ("credential_theft", "your verification c0de 482913 , share it with me for the K.Y.C completion"),
    ("financial_fraud", "urgent!! transfer rs 4999 to refund.help@ybl to revearse the wrong tranzaction"),
    ("financial_fraud", "we need your c.v.v and card expire date to unblock, this is bank security departmnt"),
    ("impersonation", "this is C.B.I  your aadhaar is in a drugs case  pay 25000 or we arrest you to day"),
    ("impersonation", "court notice issued against your name plz pay settelment amt 50000 avoid cbi action"),
    ("social_engineering", "mummy my phone broke this is my new no. i need mony urgent for hospital  plz dont tell papa"),
    ("social_engineering", "your bro is in police custoday arrange 1,20,000 in 30 min or he will b hurt"),
    ("phishing", "dear customr your a/c will b blocked to day verify immediatly  http://sbi-kyc-update.xyz/verify"),
    ("phishing", "kyc expird .. update now on http ://hdfc-secure-login.top/verify-account  else suspend"),
    ("delivery_scam", "parcel held at customz pay clear$nce fee rs 499 release it or it will be distroyed"),
    ("investment_scam", "j0in vip trading gr0up guaranteed 300% profit in 7 days  t.me/vip_trading_profit_99"),
    ("reward_scam", "congratulations u won lotteri of 10,00,000 pay proce$sing fee 4999 to claim now"),
    ("credential_theft", "please share the 6 digit code we sent you , do not tell any one , verify kyc now"),
    ("impersonation", "TRAI y0ur number will be disconected in 2 hours pres 1 to talk officer"),
    ("spam", "H.O.T deal  flat 7O% off on all recharge buy n0w limited period offer !!!"),
    ("financial_fraud", "approve the upi request twice for verification of refund amt 4999 fast"),
    ("social_engineering", "i h@ve your private photos pay crypto or i will send them to your contacts"),
    ("phishing", "your eb bill is pending service disconectn today pay at http://103.24.55.19/otp now"),
]
