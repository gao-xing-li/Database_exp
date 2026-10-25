"use strict";
const $ = selector => document.querySelector(selector);
const state = {user:null, csrf:"", products:[], orderProducts:[], orders:[], lookups:{}, tab:"products", detail:null, searches:{products:"",inventory:""}, productRequest:0, orderRequest:0, pickerRequest:0, detailRequest:0};
const roles = {manager:"店长 / 管理员",clerk:"销售 / 收银",inventory:"库存管理员",customer:"顾客"};
const roleViews = {
  manager:{tabs:["products","inventory","orders"],home:"products",products:"商品管理",orders:"销售订单"},
  clerk:{tabs:["products","orders"],home:"products",products:"商品目录",orders:"销售订单"},
  inventory:{tabs:["inventory"],home:"inventory",products:"商品目录",orders:"销售订单"},
  customer:{tabs:["products","orders"],home:"products",products:"商品目录",orders:"我的订单"}
};
const names = {ON_SALE:"在售",PENDING:"待上架",STOPPED:"停售",CREATED:"草稿",COMPLETED:"已完成",CANCELLED:"已取消"};
const esc = value => String(value ?? "").replace(/[&<>"']/g, c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const money = value => Number(value || 0).toFixed(2);
const sales = () => ["manager","clerk"].includes(state.user?.role);
const policy = () => roleViews[state.user.role];
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
  if (!state.user) {
    state.products=[];state.orderProducts=[];state.orders=[];state.lookups={};state.detail=null;
    state.searches={products:"",inventory:""};state.productRequest++;state.orderRequest++;state.pickerRequest++;state.detailRequest++;
    $("#search").value="";$("#product-rows").innerHTML="";$("#order-rows").innerHTML="";$("#detail-panel").innerHTML="";
    document.querySelectorAll("dialog[open]").forEach(dialog=>dialog.close());
    return;
  }
  $("#user-label").textContent=`${state.user.username} · ${roles[state.user.role]}`;
  const view=policy(), labels={products:view.products,inventory:"库存管理",orders:view.orders};
  document.querySelectorAll("nav [data-tab]").forEach(button=>{
    const index=view.tabs.indexOf(button.dataset.tab);
    button.hidden=index<0;
    button.firstChild.textContent=labels[button.dataset.tab]+" ";
    button.querySelector("span").textContent=index<0?"":String(index+1).padStart(2,"0");
  });
  $("#add-product").hidden=state.user.role!=="manager"||state.tab!=="products";
  $("#new-order").hidden=!sales();
  $("#orders-title").textContent=view.orders;
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
function renderMetrics(loading=false) {
  const customer=state.user.role==="customer", stock=state.tab==="inventory", orders=state.tab==="orders";
  $("#page-metrics").hidden=customer&&!orders;
  let values;
  if(orders) {
    values=[[customer?"我的订单":"订单数量",state.orders.length,"当前列表，最多200笔订单"],
      [customer?"进行中":"待结账",state.orders.filter(o=>o.order_status==="CREATED"&&(customer||o.order_type==="SPOT")).length,customer?"尚未完成的本人订单":"允许继续编辑的现货草稿"],
      ["已完成",state.orders.filter(o=>o.order_status==="COMPLETED").length,customer?"已完成的本人订单":"已保存成交记录的订单"]];
  } else if(stock) {
    values=[["库存商品",state.products.length,"当前检索结果，最多200件"],
      ["可售数量",state.products.reduce((s,p)=>s+Number(p.available_qty||0),0),"实际库存减预留库存"],
      ["需要补货",state.products.filter(p=>p.available_qty!==null&&p.available_qty<=p.reorder_point).length,"可售数量达到或低于警戒值"]];
  } else if(state.user.role==="manager") {
    values=[["商品数量",state.products.length,"当前检索结果，最多200件"],
      ["在售商品",state.products.filter(p=>p.product_status==="ON_SALE").length,"当前列表已上架商品"],
      ["非在售商品",state.products.filter(p=>p.product_status!=="ON_SALE").length,"待上架或停售商品"]];
  } else {
    values=[["目录商品",state.products.length,"当前检索结果，最多200件"],
      ["在售商品",state.products.filter(p=>p.product_status==="ON_SALE").length,"当前列表可销售商品"],
      ["可售数量",state.products.filter(p=>p.product_status==="ON_SALE").reduce((s,p)=>s+Number(p.available_qty||0),0),"当前列表在售商品可售合计"]];
  }
  ["products","stock","low"].forEach((key,index)=>{
    $("#metric-"+key+"-label").textContent=values[index][0];
    $("#metric-"+key).textContent=loading?"—":values[index][1];
    $("#metric-"+key+"-hint").textContent=values[index][2];
  });
}
async function loadProducts() {
  const request=++state.productRequest,user=state.user.user_id,tab=state.tab,term=$("#search").value;
  state.searches[tab]=term;
  const products=await api("/products?q="+encodeURIComponent(term));
  if(request!==state.productRequest||state.user?.user_id!==user||state.tab!==tab)return;
  state.products=products;renderProducts();
}
async function loadOrderProducts() {
  const request=++state.pickerRequest,user=state.user.user_id;
  $("#new-order").disabled=true;
  const products=await api("/products");
  if(request!==state.pickerRequest||state.user?.user_id!==user)return;
  state.orderProducts=products;$("#new-order").disabled=false;
}
function renderProducts(loading=false) {
  const inventoryView=state.tab==="inventory", manager=state.user.role==="manager", customer=state.user.role==="customer";
  const headings=inventoryView?["商品","实际库存","预留库存","可售库存","补货警戒值","库存状态","操作"]
    :manager?["商品","类别 / IP","售价","上架状态","操作"]
    :customer?["商品","类别 / IP","售价","可售库存"]:["商品","类别 / IP","售价","可售库存","上架状态"];
  $("#product-headings").innerHTML=`<tr>${headings.map((label,i)=>`<th${i===headings.length-1&&["操作"].includes(label)?' class="right"':""}>${label}</th>`).join("")}</tr>`;
  $("#product-foot").textContent=inventoryView?"可售库存 = 实际库存 − 预留库存":manager?"维护商品资料、售价与上架状态，库存数量在库存管理中处理。":customer?`当前显示${state.products.length}件在售商品，最多展示200件。`:"查看售价与可售库存，结账在销售订单中完成。";
  renderMetrics(loading);
  if(loading){$("#product-rows").innerHTML=`<tr><td colspan="${headings.length}" class="empty">正在加载商品…</td></tr>`;return;}
  $("#product-rows").innerHTML=state.products.map(p=>{
    const product=`<td><div class="product-cell"><span class="product-icon">${esc(p.category_name.slice(0,1))}</span><div><strong>${esc(p.product_name)}</strong><small>${esc(p.product_code)}</small></div></div></td>`;
    const status=`<td><span class="badge ${p.product_status==="STOPPED"?"gray":p.product_status==="PENDING"?"warn":""}">${esc(names[p.product_status])}</span></td>`;
    if(inventoryView) {
      const hasStock=p.on_hand_qty!==null,low=hasStock&&p.available_qty<=p.reorder_point;
      const stockValue=value=>hasStock?esc(value):"—";
      const action=["manager","inventory"].includes(state.user.role)?`<button data-action="adjust-stock" data-id="${p.product_id}">调库存</button>`:"";
      return `<tr>${product}<td>${stockValue(p.on_hand_qty)}</td><td>${stockValue(p.reserved_qty)}</td><td>${stockValue(p.available_qty)}</td><td>${stockValue(p.reorder_point)}</td><td><span class="badge ${!hasStock?"gray":low?"warn":""}">${!hasStock?"未登记库存":low?"需要补货":"充足"}</span></td><td><div class="actions">${action}</div></td></tr>`;
    }
    const info=`${product}<td>${esc(p.category_name)}<small>${esc(p.ip_name||"未指定 IP")}${p.character_name?" · "+esc(p.character_name):""}</small></td><td>¥ ${money(p.sale_price)}</td>`;
    if(manager)return `<tr>${info}${status}<td><div class="actions"><button data-action="edit-product" data-id="${p.product_id}">编辑</button><button class="danger" data-action="delete-product" data-id="${p.product_id}">删除</button></div></td></tr>`;
    return `<tr>${info}<td>${p.available_qty===null?"暂无库存":esc(p.available_qty)}</td>${customer?"":status}</tr>`;
  }).join("")||`<tr><td colspan="${headings.length}" class="empty">没有找到商品，试试其他关键词。</td></tr>`;
}
async function switchTab(tab) {
  if(!state.user)return;
  const view=policy();if(!view.tabs.includes(tab))tab=view.home;
  if(["products","inventory"].includes(state.tab))state.searches[state.tab]=$("#search").value;
  state.tab=tab;state.detail=null;state.detailRequest++;
  if(tab!=="orders")$("#search").value=state.searches[tab];
  $("#add-product").hidden=state.user.role!=="manager"||tab!=="products";
  document.querySelectorAll("[data-tab]").forEach(el=>el.classList.toggle("active",el.dataset.tab===tab));
  const title={products:view.products,inventory:"库存管理",orders:view.orders}[tab];
  $("#page-title").textContent=title;$("#breadcrumb").textContent=title;
  $("#page-description").textContent=tab==="inventory"?"查询库存，登记入库与盘点调整。":tab==="orders"?(state.user.role==="customer"?"查看本人的订单状态与成交明细。":"创建草稿、维护明细并完成现货结账。"):state.user.role==="manager"?"维护商品资料、售价与上架状态。":"浏览商品，查看价格与可售数量。";
  $("#product-panel").hidden=tab==="orders";$("#order-panel").hidden=tab!=="orders";
  $("#inventory-note").hidden=tab!=="inventory";$("#detail-panel").hidden=true;
  if(tab==="orders")await Promise.all([loadOrders(),sales()?loadOrderProducts():Promise.resolve()]);
  else{renderProducts(true);await loadProducts();}
}
async function loadOrders() {
  const request=++state.orderRequest,user=state.user.user_id;
  renderMetrics(true);$("#order-rows").innerHTML='<tr><td colspan="6" class="empty">正在加载订单…</td></tr>';
  const orders=await api("/orders");
  if(request!==state.orderRequest||state.user?.user_id!==user||state.tab!=="orders")return;
  state.orders=orders;renderMetrics();
  $("#order-rows").innerHTML=state.orders.map(o=>`<tr><td><strong>${esc(o.order_no)}</strong><small>${o.order_type==="SPOT"?"现货销售":"预售提货"}</small></td><td>${o.member_id?"会员 #"+esc(o.member_id):"散客"}</td><td><span class="badge ${o.order_status==="CREATED"?"warn":o.order_status==="CANCELLED"?"gray":""}">${esc(names[o.order_status])}</span></td><td>${esc(o.item_count)} 项 / ¥ ${money(o.amount)}</td><td>${esc(o.order_time?.replace("T"," ")||"—")}</td><td><button data-action="view-order" data-id="${o.order_id}">查看详情</button></td></tr>`).join("")||'<tr><td colspan="6" class="empty">暂无订单记录。</td></tr>';
}
async function refreshOrders() {
  const user=state.user?.user_id,current=!$("#detail-panel").hidden?state.detail?.order.order_id:null;
  await Promise.all([loadOrders(),sales()?loadOrderProducts():Promise.resolve()]);
  if(state.user?.user_id!==user||state.tab!=="orders")return;
  if(current) {
    try{await viewOrder(current);}
    catch(error){if(state.user?.user_id===user){state.detail=null;$("#detail-panel").hidden=true;}throw error;}
  }
  if(state.user?.user_id===user&&state.tab==="orders")notice(sales()?"订单与可选商品已更新，本单单价保持不变。":"订单信息已更新。");
}
async function viewOrder(id) {
  const request=++state.detailRequest,user=state.user?.user_id;
  const detail=await api("/orders/"+id);
  if(request!==state.detailRequest||state.user?.user_id!==user||state.tab!=="orders")return;
  state.detail=detail;
  const {order:o,items,amount}=state.detail, editable=sales()&&o.order_status==="CREATED"&&o.order_type==="SPOT";
  $("#detail-panel").hidden=false;
  $("#detail-panel").innerHTML=`<div class="order-summary"><h2>${esc(o.order_no)} <span class="badge">${esc(names[o.order_status])}</span></h2><strong>¥ ${money(amount)}</strong></div><p class="hint">${editable?"按登记时的目录标价结账，修改数量和刷新均保留本单单价。完成后明细只读。":"订单信息和成交价格已留存，可在此核对交易明细。"}</p>${editable?`<div class="order-tools"><label>购买会员</label><select id="detail-member">${memberOptions()}</select><button data-action="save-member" data-id="${id}">修改会员</button></div>`:""}<div class="table-wrap"><table><thead><tr><th>商品</th><th>数量</th><th>单价</th><th>金额</th>${editable?"<th>操作</th>":""}</tr></thead><tbody>${items.map(i=>`<tr><td>${esc(i.product_name)}<small>${esc(i.product_code)}</small></td><td>${editable?`<input aria-label="${esc(i.product_name)}数量" class="qty-input" id="qty-${i.product_id}" type="number" min="1" max="1000000" value="${i.quantity}">`:i.quantity}</td><td>¥ ${money(i.unit_price)}</td><td>¥ ${money(i.amount)}</td>${editable?`<td><button data-action="save-item" data-id="${i.product_id}">更新数量</button> <button class="danger" data-action="delete-item" data-id="${i.product_id}">移除</button></td>`:""}</tr>`).join("")||`<tr><td colspan="5" class="empty">尚未添加商品明细。</td></tr>`}</tbody></table></div>${editable?`<div class="order-tools"><select id="item-product" aria-label="添加商品">${state.orderProducts.filter(p=>p.product_status==="ON_SALE").map(p=>option(p.product_id,`${p.product_name} · 当前标价¥${money(p.sale_price)} · 可售${p.available_qty??0}`)).join("")}</select><input id="item-qty" type="number" min="1" max="1000000" value="1" aria-label="购买数量"><button data-action="add-item">添加 / 替换数量</button></div><div class="dialog-actions"><button class="danger" data-action="delete-order" data-id="${id}">删除草稿</button><button data-action="cancel-order" data-id="${id}">取消订单</button><button class="primary" data-action="checkout" data-id="${id}">确认结账</button></div>`:""}`;
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
    case "refresh-orders":await refreshOrders();return;
    case "view-order":await viewOrder(id);return;
    case "save-member":await api(`/orders/${id}`,"PATCH",{member_id:$("#detail-member").value||null});break;
    case "save-item":await api(`/orders/${current}/items/${id}`,"PUT",{quantity:$("#qty-"+id).value});break;
    case "delete-item":await api(`/orders/${current}/items/${id}`,"DELETE");break;
    case "add-item":if(!$("#item-product").value)throw new Error("请先选择商品");if(!$("#item-qty").checkValidity())throw new Error("数量必须为1至1000000的整数");await api(`/orders/${current}/items/${$("#item-product").value}`,"PUT",{quantity:$("#item-qty").value,expected_unit_price:state.orderProducts.find(p=>String(p.product_id)===$("#item-product").value)?.sale_price});break;
    case "checkout":if(!confirm(`确认按本单明细结账，共 ¥${money(state.detail?.amount)}，并扣减库存？`))return;await api(`/orders/${id}/checkout`,"POST",{});await loadOrderProducts();break;
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
async function initialize(){if(!state.user){showSession();return;}state.lookups=await api("/lookups");fillLookups();await switchTab(policy().home);showSession();}
(async()=>{try{const value=await api("/session");state.user=value.user;state.csrf=value.csrf_token;await initialize();}catch(error){notice(error.message,true);}})();
