"""Compositional fragment pools for the Message Shield corpus.

A generated message is built from role fragments:
    opener + core + [pressure] + [close]

Fragments carry the class-specific vocabulary, but slots (bank, amount, url...)
are sampled independently, so the space of sentences is much larger than the
authored template list. Fragments are split at fragment level by a stable
hash: **validation and test messages are built only from fragments reserved
for them**, so the held-out set measures generalisation to wording the model
never trained on rather than memorisation of near-duplicate templates.
"""

OPENERS = {
    "legitimate": [
        "Dear customer,", "Hello {name},", "Hi {name},", "{bank}:", "{brand} update:",
        "Good morning,", "Aapko suchit kiya jata hai ki", "Team {courier} ki taraf se,",
    ],
    "spam": [
        "HOT OFFER!", "Limited period deal!", "Big sale alert!", "Attention!", "Sabse sasta offer!",
        "Don't miss out!", "Special offer for you!",
    ],
    "phishing": [
        "Dear customer,", "Dear user,", "Dear valued customer,", "{bank} security notice:",
        "{brand}:", "Important notice:", "Dear account holder,",
    ],
    "financial_fraud": [
        "I am {name} from the {bank} fraud department.", "Hello sir, this is {wallet} support.",
        "Sir I am calling from {bank} customer care.", "Our {bank} officer here.",
        "Hello, this is the {bank} verification team.", "I am the {bank} nodal officer speaking.",
    ],
    "credential_theft": [
        "Bank security: ", "Sir, ", "Hello, ", "Support desk here: ", "Aapka bank verification ke liye: ",
        "Dear sir/madam, ",
    ],
    "impersonation": [
        "This is {gov}.", "I am calling from {bank} head office.", "Cyber Crime Branch:",
        "{gov} notice:", "This is the police.", "{courier} legal cell:", "TRAI order:",
    ],
    "social_engineering": [
        "Please help me.", "Mummy,", "Listen carefully.", "I am your {name}'s friend.",
        "This is urgent.", "Papa,", "Bhai please,",
    ],
    "investment_scam": [
        "Join our VIP trading group!", "Guaranteed returns plan:", "Investment opportunity:",
        "Work from home job offer:", "Our SEBI registered expert says:", "Part time job alert:",
        "Crypto earning plan:",
    ],
    "reward_scam": [
        "Congratulations!", "You are the lucky winner!", "{bank} anniversary offer:",
        "Great news!", "Lucky draw result:", "{brand} gift alert:",
    ],
    "delivery_scam": [
        "{courier}:", "Delivery failed alert:", "Customs department notice:",
        "Your parcel update:", "Shipping alert:", "Courier service message:",
    ],
}

CORES = {
    "legitimate": [
        "{digits} is your OTP for net banking login.",
        "{digits} is the one time password for a transaction of Rs.{amount}.",
        "Rs.{amount} has been debited from your {bank} account XX4321.",
        "Rs.{amount} was credited to your account by salary.",
        "Your account statement for {month} is ready in the app.",
        "your order for {item} has been delivered by 7 pm.",
        "your electricity bill of Rs.{amount} is due on {day}.",
        "your KYC is already updated and verified, no action is required.",
        "your {wallet} wallet balance is Rs.{amount}.",
        "your complaint ticket 44512 has been resolved.",
        "aapka {bank} account me Rs.{amount} credit hua hai.",
        "main aaj thoda late aaunga, dinner meri taraf se ghar par hai.",
    ],
    "spam": [
        "Flat 70 percent off on all recharge packs.",
        "Get one free product on every purchase.",
        "Lowest interest loan with instant approval and no documents.",
        "Free gift voucher worth Rs.{amount} for you.",
        "Increase your followers instantly with our service.",
        "Weight loss plan with guaranteed results in 7 days.",
        "Adult chat and dating service in your city.",
        "Earn daily payouts from home without any investment.",
        "Sabse sasta data pack aur recharge available.",
    ],
    "phishing": [
        "your account will be blocked today.",
        "your KYC has expired and service will stop within 24 hours.",
        "your parcel is held and needs an address confirmation.",
        "your payment failed and the account needs re-verification.",
        "a refund of Rs.{amount} is pending in your name.",
        "an unusual login was detected on your account.",
        "your electricity connection will be disconnected {day}.",
        "your debit card has been suspended temporarily.",
        "your {wallet} account requires immediate re-verification.",
        "your shipment is on hold at the customs facility.",
    ],
    "financial_fraud": [
        "your card is compromised, confirm the 16 digit card number and CVV so we can block it.",
        "send Rs.{amount} to {upi} and we will reverse the wrong transaction instantly.",
        "share the 6 digit code we sent to complete your pending refund.",
        "pay the processing fee of Rs.{amount} to release your approved loan.",
        "transfer Rs.{amount} back to {upi} because it was credited by mistake.",
        "approve the collect request of Rs.{amount} in your UPI app as verification.",
        "your EMI failed, pay Rs.{amount} right now to protect your credit score.",
        "we need your card expiry date and CVV to process the refund.",
        "our officer will guide you to pay Rs.{amount} to {upi} for customs duty.",
    ],
    "credential_theft": [
        "share the OTP you just received with our officer immediately.",
        "please provide the 6 digit verification code to complete KYC.",
        "I am sending an OTP on your number, tell me the code to activate the SIM.",
        "enter your net banking user id, password and PIN to avoid deactivation.",
        "we need your CVV and card expiry to reverse the failed charge.",
        "reply with your user id and password to continue the session.",
        "read the code sent to your phone for identity verification.",
        "forward the WhatsApp code you received to this number.",
        "apna UPI PIN share karein verification ke liye.",
        "share the security code and CVV with the support agent.",
    ],
    "impersonation": [
        "your account is used for money laundering and you will be arrested.",
        "your PAN is linked to illegal transactions, pay a penalty of Rs.{amount}.",
        "an FIR has been registered against you, join the video call for verification.",
        "your Aadhaar was found in a drugs case, do not tell anyone.",
        "your parcel contains illegal items, pay Rs.{amount} or face arrest.",
        "your number will be disconnected in 2 hours due to illegal activity.",
        "your {gov} scheme installment needs your Aadhaar and bank details.",
        "a court notice is issued in your name, pay Rs.{amount} to close the case.",
        "your account is under investigation, transfer Rs.{amount} for verification.",
        "a warrant will be issued tonight unless you settle the fine of Rs.{amount}.",
    ],
    "social_engineering": [
        "I met with an accident and need Rs.{amount} urgently.",
        "my phone broke, this is my new number and I need money for the hospital.",
        "your daughter's friend is in trouble and needs money right now.",
        "your brother is in police custody, arrange Rs.{amount} in 30 minutes.",
        "I have your private photos and will send them to your contacts.",
        "pay in crypto or I will upload your chats online.",
        "we recorded your parcel with illegal items, pay to avoid jail.",
        "your son is detained at the airport, pay Rs.{amount} and stay on the call.",
        "you are under digital arrest, keep the video call on and transfer the money.",
        "send the money to {upi} immediately and tell nobody about this.",
    ],
    "investment_scam": [
        "earn 300 percent profit in 7 days with our assured plan.",
        "invest Rs.{amount} and earn Rs.{amount2} daily, guaranteed.",
        "our expert will double your capital in the equity market, no risk.",
        "crypto mining plan pays 5 percent daily fixed returns.",
        "work from home data entry job pays Rs.{amount} per day.",
        "pay a registration fee of Rs.{amount3} to start your part time job.",
        "your loan is approved, pay the processing fee of Rs.{amount} to {upi}.",
        "our trading bot gives 42 percent monthly returns, deposit USDT today.",
        "guaranteed doubling scheme, invest Rs.{amount2} and get double in 90 days.",
        "sarkari yojana ke tahat free loan, sirf Rs.{amount} processing fee.",
    ],
    "reward_scam": [
        "you won a lottery of Rs.{amount2}, pay Rs.{amount} to claim it.",
        "your number won Rs.{amount2} in the lucky draw, share bank details.",
        "a cashback of Rs.{amount} is waiting, claim it within 30 minutes.",
        "you are the lucky winner of a smartphone, pay the delivery charge.",
        "your scratch card won Rs.{amount}, tell us the code we sent.",
        "pay the courier charge of Rs.{amount} to receive your prize.",
        "claim your Rs.{amount2} voucher by paying a verification charge.",
        "prize money of Rs.{amount2} needs a tax payment of Rs.{amount}.",
    ],
    "delivery_scam": [
        "your parcel could not be delivered due to an incomplete address.",
        "your package is stuck at customs, pay the clearance fee of Rs.{amount}.",
        "delivery was attempted today, reschedule by paying Rs.{amount}.",
        "illegal items were found in your shipment, pay a customs penalty.",
        "your order is on hold, pay the handling fee of Rs.{amount}.",
        "customs duty of Rs.{amount} is unpaid, the parcel will be returned.",
        "your international courier needs a redelivery fee of Rs.{amount}.",
        "returned to warehouse, pay Rs.{amount} to reschedule the delivery.",
    ],
}

PRESSURES = {
    "legitimate": [
        "Do not share this OTP with anyone, including bank staff.",
        "Never share your OTP, PIN or CVV with anyone.",
        "If this was not you, call our official helpline 1800123456.",
        "This code is valid for 10 minutes only.",
        "Bank staff never asks for your OTP or PIN.",
        "To unsubscribe reply STOP.",
        "Koi OTP ya PIN kisi ke saath share na karein.",
    ],
    "spam": [
        "Hurry, offer ends tonight!",
        "Reply YES to claim now.",
        "Very limited stock available.",
        "Call {phone} for details.",
        "Terms and conditions apply.",
    ],
    "phishing": [
        "Verify immediately or your account will be suspended.",
        "Update your details within 24 hours to avoid deactivation.",
        "Failure to verify will result in permanent closure.",
        "Confirm your identity today to keep the service active.",
        "Act now, this link expires in 12 hours.",
    ],
    "financial_fraud": [
        "This is urgent, do it now or the money will be lost.",
        "Do not disconnect the call, I will guide you step by step.",
        "Keep this confidential, bank policy does not allow sharing.",
        "Please cooperate, the request is time sensitive.",
    ],
    "credential_theft": [
        "This is required for security verification, do it immediately.",
        "Do not tell anyone, this is a confidential verification.",
        "The code expires in 60 seconds, tell me quickly.",
        "Otherwise your account will be blocked today.",
    ],
    "impersonation": [
        "You must cooperate or you will be arrested today.",
        "Do not inform anyone, this is a confidential investigation.",
        "A legal case will be filed and you will be detained.",
        "Pay immediately to avoid a non-bailable warrant.",
        "Stay on the video call, we are monitoring your location.",
    ],
    "social_engineering": [
        "Please hurry, there is very little time.",
        "Do not tell anyone in the family, they will panic.",
        "I will be in trouble if you delay even a little.",
        "You are the only one who can help me right now.",
        "This is my last warning, pay or face the consequences.",
    ],
    "investment_scam": [
        "Guaranteed profit, zero risk, join today only.",
        "Limited seats in the VIP group, pay now.",
        "Withdraw anytime, 100 percent assured returns.",
        "Members are already earning daily payouts.",
    ],
    "reward_scam": [
        "Claim before the offer expires today.",
        "Pay the small processing fee to receive the amount.",
        "Offer valid for selected numbers only.",
        "Provide your bank details to receive the prize money.",
    ],
    "delivery_scam": [
        "Pay now to avoid the parcel being destroyed.",
        "The parcel will be returned if the fee is not paid today.",
        "A police case will be filed if duty is unpaid.",
        "Redelivery must be paid within 12 hours.",
    ],
}

CLOSES = {
    "legitimate": [
        "Login in the official app for details.",
        "No action is required from your side.",
        "Reply here if you need help.",
        "Thanks for banking with {bank}.",
        "Have a good day.",
        "Dhanyavaad.",
    ],
    "spam": [
        "Visit {url} today!",
        "WhatsApp {phone} for the price list.",
        "Order now, stocks are limited.",
        "Click here to shop.",
        "Reply STOP to unsubscribe.",
    ],
    "phishing": [
        "Verify here: {url}",
        "Update now at {url}",
        "Click {url} to complete verification.",
        "Confirm your details at {url} immediately.",
        "Re-verify at {url} within 12 hours.",
    ],
    "financial_fraud": [
        "Confirm quickly on this call.",
        "Share the details so I can process it.",
        "Transfer to {upi} and send me the screenshot.",
        "Reply with the OTP to complete the reversal.",
    ],
    "credential_theft": [
        "Reply with the code immediately.",
        "Share it with me on this call.",
        "Enter the details at {url} to continue.",
        "Send the code to {phone} for verification.",
    ],
    "impersonation": [
        "Pay Rs.{amount} to {upi} immediately.",
        "Transfer the settlement amount right now.",
        "Join the call at {url} for verification.",
        "Contact this officer number {phone} today.",
    ],
    "social_engineering": [
        "Transfer to {upi} right now.",
        "Send it to {upi} and keep quiet about this.",
        "Send crypto to this wallet address today.",
        "Reply to this new number only.",
    ],
    "investment_scam": [
        "Join here: {url}",
        "Contact {phone} to start.",
        "Pay to {upi} and start earning today.",
        "WhatsApp {phone} for the plan.",
    ],
    "reward_scam": [
        "Claim now at {url}",
        "Pay Rs.{amount} to {upi} to receive the prize.",
        "Share your bank details for credit.",
        "Contact {phone} to claim.",
    ],
    "delivery_scam": [
        "Pay at {url} to release the parcel.",
        "Pay Rs.{amount} to {upi} for clearance.",
        "Update at {url} within 6 hours.",
        "Call {phone} for the payment link.",
    ],
}

ROLES = {
    "legitimate": (OPENERS, CORES, PRESSURES, CLOSES),
    "spam": (OPENERS, CORES, PRESSURES, CLOSES),
    "phishing": (OPENERS, CORES, PRESSURES, CLOSES),
    "financial_fraud": (OPENERS, CORES, PRESSURES, CLOSES),
    "credential_theft": (OPENERS, CORES, PRESSURES, CLOSES),
    "impersonation": (OPENERS, CORES, PRESSURES, CLOSES),
    "social_engineering": (OPENERS, CORES, PRESSURES, CLOSES),
    "investment_scam": (OPENERS, CORES, PRESSURES, CLOSES),
    "reward_scam": (OPENERS, CORES, PRESSURES, CLOSES),
    "delivery_scam": (OPENERS, CORES, PRESSURES, CLOSES),
}
