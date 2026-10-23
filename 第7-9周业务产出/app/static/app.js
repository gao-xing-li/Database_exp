"use strict";
const $ = selector => document.querySelector(selector);
const state = {user:null, csrf:"", products:[], orders:[], lookups:{}, tab:"products", detail:null};
const roles = {manager:"店长 / 管理员",clerk:"销售 / 收银",inventory:"库存管理员",customer:"顾客"};
const names = {ON_SALE:"在售",PENDING:"待上架",STOPPED:"停售",CREATED:"草稿",COMPLETED:"已完成",CANCELLED:"已取消"};
const esc = value => String(value ?? "").replace(/[&<>"']/g, c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const money = value => Number(value || 0).toFixed(2);
const sales = () => ["manager","clerk"].includes(state.user?.role);
let noticeTimer;
function notice(message, error=false) {clearTimeout(noticeTimer); $("#notice").textContent=message; $("#notice").classList.toggle("error",error); $("#notice").hidden=false; noticeTimer=setTimeout(()=>$("#notice").hidden=true,error?12000:4000);}
async function api(path, method="GET", body) {
  const response=await fetch("/api"+path,{method,headers:{"Content-Type":"application/json","X-CSRF-Token":state.csrf},...(body===undefined?{}:{body:JSON.stringify(body)})});
  const value=await response.json();
  if (!response.ok) {
    if (value.code==="AUTH_REQUIRED") {state.user=null; showSession();}
    throw new Error(`${value.message}（编号 ${value.request_id}）`);
  }
  return value.data;
}
function showSession() {
  $("#login-screen").hidden=!!state.user; $("#workspace").hidden=!state.user;
  if (!state.user) return;
  $("#user-label").textContent=`${state.user.username} · ${roles[state.user.role]}`;
  $("#add-product").hidden=state.user.role!=="manager";
  $("#nav-inventory").hidden=state.user.role==="customer";
  $("#nav-orders").hidden=state.user.role==="inventory";
  $("#new-order").hidden=!sales();
  $("#orders-title").textContent=state.user.role==="customer"?"我的订单":"销售订单";
}
const option = (id,label)=>`<option value="${esc(id)}">${esc(label)}</option>`;
function fillLookups() {
  const form=$("#product-form");
  form.category_id.innerHTML=state.lookups.categories.map(x=>option(x.category_id,x.category_name)).join("");
  form.ip_id.innerHTML=option("","不指定 IP")+state.lookups.ips.map(x=>option(x.ip_id,x.ip_name)).join("");
  form.character_id.innerHTML=option("","不指定具体角色")+state.lookups.characters.map(x=>option(x.character_id,x.character_name)).join("");
  $("#new-order-form").member_id.innerHTML=memberOptions();
}
function memberOptions() {return option("","散客 / 非会员")+(state.lookups.members||[]).map(x=>option(x.member_id,`${x.member_no} · ${x.member_name}`)).join("");}
async function loadProducts() {state.products=await api("/products?q="+encodeURIComponent($("#search").value));renderProducts();}
function renderProducts() {
  $("#metric-products").textContent=state.products.length;
  $("#metric-stock").textContent=state.products.reduce((s,p)=>s+Number(p.available_qty||0),0);
  $("#metric-low").textContent=state.products.filter(p=>p.available_qty!==null&&p.available_qty<=p.reorder_point).length;
  $("#product-rows").innerHTML=state.products.map(p=>`<tr><td><div class="product-cell"><span class="product-icon">${esc(p.category_name.slice(0,1))}</span><div><strong>${esc(p.product_name)}</strong><small>${esc(p.product_code)}</small></div></div></td><td>${esc(p.category_name)}<small>${esc(p.ip_name||"未指定 IP")}${p.character_name?" · "+esc(p.character_name):""}</small></td><td>¥ ${money(p.sale_price)}</td><td>${p.available_qty===null?"未建库存":`${esc(p.available_qty)} <span class="muted">/ ${esc(p.reserved_qty)}</span>`}<small>警戒 ${esc(p.reorder_point??"—")}</small></td><td><span class="badge ${p.product_status==="STOPPED"?"gray":p.product_status==="PENDING"?"warn":""}">${esc(names[p.product_status])}</span>${p.available_qty!==null&&p.available_qty<=p.reorder_point?'<small class="danger">需要补货</small>':""}</td><td><div class="actions">${state.user.role==="manager"?`<button data-action="edit-product" data-id="${p.product_id}">编辑</button><button class="danger" data-action="delete-product" data-id="${p.product_id}">删除</button>`:""}${["manager","inventory"].includes(state.user.role)?`<button data-action="adjust-stock" data-id="${p.product_id}">调库存</button>`:""}${!["manager","inventory"].includes(state.user.role)?'<span class="muted">可浏览</span>':""}</div></td></tr>`).join("")||'<tr><td colspan="6" class="empty">没有找到商品，试试其他关键词。</td></tr>';
}
async function switchTab(tab) {
  state.tab=tab;
  document.querySelectorAll("[data-tab]").forEach(el=>el.classList.toggle("active",el.dataset.tab===tab));
  const title={products:"商品目录",inventory:"库存管理",orders:state.user.role==="customer"?"我的订单":"销售订单"}[tab];
  $("#page-title").textContent=title; $("#breadcrumb").textContent=title;
  $("#page-description").textContent={products:"整理每一种喜欢，了解每一件商品。",inventory:"掌握库存余量，让每一件商品各得其所。",orders:"从一张草稿开始，认真完成每一笔交易。"}[tab];
  $("#product-panel").hidden=tab==="orders"; $("#order-panel").hidden=tab!=="orders";
  $("#inventory-note").hidden=tab!=="inventory";$("#detail-panel").hidden=true;
  if(tab==="orders") await loadOrders(); else await loadProducts();
}
async function loadOrders() {
  state.orders=await api("/orders");
  $("#order-rows").innerHTML=state.orders.map(o=>`<tr><td><strong>${esc(o.order_no)}</strong><small>${o.order_type==="SPOT"?"现货销售":"预售提货"}</small></td><td>${o.member_id?"会员 #"+esc(o.member_id):"散客"}</td><td><span class="badge ${o.order_status==="CREATED"?"warn":o.order_status==="CANCELLED"?"gray":""}">${esc(names[o.order_status])}</span></td><td>${esc(o.item_count)} 项 / ¥ ${money(o.amount)}</td><td>${esc(o.order_time?.replace("T"," ")||"—")}</td><td><button data-action="view-order" data-id="${o.order_id}">查看详情</button></td></tr>`).join("")||'<tr><td colspan="6" class="empty">暂无订单记录。</td></tr>';
}
async function viewOrder(id) {
  state.detail=await api("/orders/"+id);
  const {order:o,items,amount}=state.detail, editable=sales()&&o.order_status==="CREATED"&&o.order_type==="SPOT";
  $("#detail-panel").hidden=false;
  $("#detail-panel").innerHTML=`<div class="order-summary"><h2>${esc(o.order_no)} <span class="badge">${esc(names[o.order_status])}</span></h2><strong>¥ ${money(amount)}</strong></div><p class="hint">${editable?"草稿金额供核对；结账按当时售价保存成交价。完成后订单和明细只读。":"订单信息和成交价格已留存，可在此核对交易明细。"}</p>${editable?`<div class="order-tools"><label>购买会员</label><select id="detail-member">${memberOptions()}</select><button data-action="save-member" data-id="${id}">修改会员</button></div>`:""}<div class="table-wrap"><table><thead><tr><th>商品</th><th>数量</th><th>单价</th><th>金额</th>${editable?"<th>操作</th>":""}</tr></thead><tbody>${items.map(i=>`<tr><td>${esc(i.product_name)}<small>${esc(i.product_code)}</small></td><td>${editable?`<input aria-label="${esc(i.product_name)}数量" class="qty-input" id="qty-${i.product_id}" type="number" min="1" max="1000000" value="${i.quantity}">`:i.quantity}</td><td>¥ ${money(i.unit_price)}</td><td>¥ ${money(i.amount)}</td>${editable?`<td><button data-action="save-item" data-id="${i.product_id}">更新数量</button> <button class="danger" data-action="delete-item" data-id="${i.product_id}">移除</button></td>`:""}</tr>`).join("")||`<tr><td colspan="5" class="empty">尚未添加商品明细。</td></tr>`}</tbody></table></div>${editable?`<div class="order-tools"><select id="item-product" aria-label="添加商品">${state.products.filter(p=>p.product_status==="ON_SALE").map(p=>option(p.product_id,`${p.product_name} · ¥${money(p.sale_price)} · 可售${p.available_qty??0}`)).join("")}</select><input id="item-qty" type="number" min="1" max="1000000" value="1" aria-label="购买数量"><button data-action="add-item">添加 / 替换数量</button></div><div class="dialog-actions"><button class="danger" data-action="delete-order" data-id="${id}">删除草稿</button><button data-action="cancel-order" data-id="${id}">取消订单</button><button class="primary" data-action="checkout" data-id="${id}">确认结账</button></div>`:""}`;
  if(editable) $("#detail-member").value=o.member_id||"";
}
function editProduct(id) {
  const form=$("#product-form");form.reset();form.product_id.value="";
  $("#product-form-title").textContent=id?"编辑商品":"新增商品";
  if(id){const product=state.products.find(p=>p.product_id===id); for(const key of ["product_id","product_code","product_name","category_id","ip_id","character_id","sale_price","product_status"]) form.elements[key].value=product[key]??"";}
  $("#product-dialog").showModal();
}
async function action(button) {
  const id=Number(button.dataset.id),current=state.detail?.order.order_id;
  switch(button.dataset.action) {
    case "edit-product":editProduct(id);return;
    case "delete-product":if(confirm("仅删除无库存、无历史关联的商品。确认删除？")){await api("/products/"+id,"DELETE");await loadProducts();}return;
    case "adjust-stock":{const p=state.products.find(p=>p.product_id===id),f=$("#inventory-form");f.reset();f.product_id.value=id;f.reorder_point.value=p.reorder_point||0;$("#inventory-product").textContent=`${p.product_name} · 实际 ${p.on_hand_qty??0} / 预留 ${p.reserved_qty??0}`;$("#inventory-dialog").showModal();return;}
    case "refresh-orders":await loadOrders();return;
    case "view-order":await viewOrder(id);return;
    case "save-member":await api(`/orders/${id}`,"PATCH",{member_id:$("#detail-member").value||null});break;
    case "save-item":await api(`/orders/${current}/items/${id}`,"PUT",{quantity:$("#qty-"+id).value});break;
    case "delete-item":await api(`/orders/${current}/items/${id}`,"DELETE");break;
    case "add-item":if(!$("#item-product").value)throw new Error("请先选择商品");if(!$("#item-qty").checkValidity())throw new Error("数量必须为1至1000000的整数");await api(`/orders/${current}/items/${$("#item-product").value}`,"PUT",{quantity:$("#item-qty").value});break;
    case "checkout":if(!confirm("确认按当前售价结账并扣减库存？"))return;await api(`/orders/${id}/checkout`,"POST",{});await loadProducts();break;
    case "cancel-order":if(!confirm("确认取消此草稿订单？"))return;await api(`/orders/${id}/cancel`,"POST",{});break;
    case "delete-order":if(!confirm("确认删除此草稿及其明细？"))return;await api(`/orders/${id}`,"DELETE");$("#detail-panel").hidden=true;await loadOrders();return;
  }
  await loadOrders();if(current)await viewOrder(current);notice("操作成功");
}
function guarded(handler) {return async event=>{event.preventDefault();const target=event.submitter||event.currentTarget;try{if(target instanceof HTMLButtonElement)target.disabled=true;await handler(event);}catch(error){notice(error.message||"连接暂不可用，请稍后重试",true);}finally{if(target instanceof HTMLButtonElement)target.disabled=false;}};}
$("#login-form").addEventListener("submit",guarded(async()=>{const data=Object.fromEntries(new FormData($("#login-form")));const value=await api("/login","POST",data);state.user=value.user;state.csrf=value.csrf_token;$("#login-form").reset();await initialize();}));
$("#logout").addEventListener("click",guarded(async()=>{await api("/logout","POST",{});state.user=null;showSession();const value=await api("/session");state.csrf=value.csrf_token;}));
$("#search-form").addEventListener("submit",guarded(loadProducts));
$("#add-product").addEventListener("click",()=>editProduct());
$("#new-order").addEventListener("click",()=>$("#new-order-dialog").showModal());
document.querySelectorAll("[data-tab]").forEach(el=>el.addEventListener("click",guarded(()=>switchTab(el.dataset.tab))));
document.addEventListener("click",event=>{const close=event.target.closest("[data-close]");if(close)$("#"+close.dataset.close).close();const button=event.target.closest("[data-action]");if(button)guarded(()=>action(button))({preventDefault(){},currentTarget:button});});
$("#product-form").addEventListener("submit",guarded(async()=>{const data=Object.fromEntries(new FormData($("#product-form"))),id=data.product_id;delete data.product_id;await api("/products"+(id?"/"+id:""),id?"PUT":"POST",data);$("#product-dialog").close();await loadProducts();notice("商品已保存");}));
$("#inventory-form").addEventListener("submit",guarded(async()=>{const data=Object.fromEntries(new FormData($("#inventory-form")));await api(`/inventory/${data.product_id}/adjust`,"POST",data);$("#inventory-dialog").close();await loadProducts();notice("库存已调整");}));
$("#new-order-form").addEventListener("submit",guarded(async()=>{const data=Object.fromEntries(new FormData($("#new-order-form"))),result=await api("/orders","POST",data);$("#new-order-dialog").close();await viewOrder(result.order_id);await loadOrders();notice("草稿已创建，请添加商品");}));
async function initialize(){showSession();if(state.user){state.lookups=await api("/lookups");fillLookups();await switchTab("products");}}
(async()=>{try{const value=await api("/session");state.user=value.user;state.csrf=value.csrf_token;await initialize();}catch(error){notice(error.message,true);}})();
